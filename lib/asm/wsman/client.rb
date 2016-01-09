require "asm/util"
require "asm/wsman/response_error"
require "logger"

module ASM
  class WsMan
    class Client
      attr_reader :endpoint, :logger

      def initialize(endpoint, options={})
        missing_params = [:host, :user, :password].reject { |k| endpoint.include?(k) }
        raise("Missing required endpoint parameter(s): %s" % [missing_params.join(", ")]) unless missing_params.empty?
        @endpoint = endpoint
        @logger = augment_logger(options.delete(:logger) || Logger.new(nil))
      end

      # @api private
      def augment_logger(logger)
        if !logger.respond_to?(:error) && logger.respond_to?(:err)
          # Puppet logger has most Logger methods, but uses err instead of error
          def logger.error(msg)
            err(msg)
          end
        end
        logger
      end

      def host
        endpoint[:host]
      end

      # Invoke the wsman CLI cient
      #
      # Will automatically retry in the case of authentication errors.
      #
      # @param endpoint [Hash]
      # @option endpoint [String] :host the iDrac host
      # @option endpoint [String] :user the iDrac user
      # @option endpoint [String] :password the iDrac password
      # @param method the wsman method. Should be one of enumerate, get or a custom invoke method
      # @param schema the wsman schema
      # @param options [Hash]
      # @option options [String] :selector an xpath expression to run. Result will be returned as a String if there is one match, an Array of Strings otherwise.
      # @option options [Hash] :props arguments to an invoke command
      # @option options [String] :input_file an XML file containing options for an invoke command
      # @option options Logger] :logger logger for debug messages
      # @option options [FixNum] :nth_attempt used internally to allow recursive retry
      # rubocop:disable Metrics/MethodLength
      def invoke(method, schema, options={})
        options = {
          :selector => nil,
          :props => {},
          :input_file => nil,
          :nth_attempt => 0
        }.merge(options)

        if %w(enumerate get).include?(method)
          args = [method, schema]
        else
          args = ["invoke", "-a", method, schema]
        end

        args += ["-h", host,
                 "-V", "-v", "-c", "dummy.cert", "-P", "443",
                 "-u", endpoint[:user],
                 "-j", "utf-8", "-m", "256", "-y", "basic", "--transport-timeout=300"]
        args += ["-J", options[:input_file]] if options[:input_file]
        options[:props].each do |key, val|
          args += ["-k", "#{key}=#{val}"]
        end

        logger.debug("Executing wsman #{args.join(' ')}")
        result = ASM::Util.run_command_with_args("env", "WSMAN_PASS=#{endpoint[:password]}",
                                                 "wsman", "--non-interactive", *args)
        logger.debug("Result = #{result}")

        # The wsman cli does not set exit_status properly on failure, so we
        # have to check stderr as well...
        unless result.exit_status == 0 && result.stderr.empty?
          if result["stdout"] =~ /Authentication failed/
            if options[:nth_attempt] < 2
              # We have seen sporadic authentication failed errors from idrac. Retry a couple times
              options[:nth_attempt] += 1
              logger.info("Authentication failed, retrying #{host}...")
              sleep 10
              return invoke(method, schema, options)
            end
            msg = "Authentication failed, please retry with correct credentials after resetting the iDrac at #{host}."
          elsif result["stdout"] =~ /Connection failed./ || result["stderr"] =~ /Connection failed./
            if options[:nth_attempt] < 2
              # We have seen sporadic connection failed errors from idrac. Retry a couple times
              options[:nth_attempt] += 1
              logger.info("Connection failed, retrying #{host}...")
              sleep 10
              return invoke(method, schema, options)
            end
            msg = "Connection failed, Couldn't connect to server. Please check IP address credentials for iDrac at #{host}."
          else
            msg = "Failed to execute wsman command against server #{host}"
          end
          logger.error(msg)
          raise(ASM::WsMan::Error, "#{msg}: #{result}")
        end

        if options[:selector]
          doc = REXML::Document.new(result["stdout"])
          options[:selector] = [options[:selector]] unless options[:selector].respond_to?(:collect)
          ret = options[:selector].collect do |selector|
            node = REXML::XPath.first(doc, selector)
            if node
              node.text
            else
              msg = "Invalid WS-MAN response from server #{host}"
              logger.error(msg)
              raise(ASM::WsMan::Error, msg)
            end
          end
          ret.size == 1 ? ret.first : ret
        else
          result["stdout"]
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
