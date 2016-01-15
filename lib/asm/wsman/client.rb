require "asm/util"
require "asm/wsman/response_error"
require "asm/wsman/parser"
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

        proxy_warn
      end

      # @api private
      def proxy_warn
        if ENV.include?("http_proxy") || ENV.include?("https_proxy")
          logger.warn("wsman invocations will use the proxy set in http_proxy or https_proxy")
        end
      end

      # @api private
      def augment_logger(logger)
        if !logger.respond_to?(:error) && logger.respond_to?(:err)
          # Puppet logger has most Logger methods, but uses err and warning
          # rubocop:disable Lint/NestedMethodDefinition
          def logger.error(msg)
            err(msg)
          end

          def logger.warn(msg)
            warning(msg)
          end
          # rubocop:enable Lint/NestedMethodDefinition
        end
        logger
      end

      def host
        endpoint[:host]
      end

      # Execute the wsman CLI cient
      #
      # Will automatically retry in the case of authentication errors.
      #
      # @param method the wsman method. Should be one of enumerate, get or a custom invoke method
      # @param schema the wsman schema
      # @param options [Hash]
      # @option options [String] :selector an xpath expression to run. Result will be returned as a String if there is one match, an Array of Strings otherwise.
      # @option options [Hash] :props arguments to an invoke command
      # @option options [String] :input_file an XML file containing options for an invoke command
      # @option options Logger] :logger logger for debug messages
      # @option options [FixNum] :nth_attempt used internally to allow recursive retry
      # @return [String]
      # rubocop:disable Metrics/MethodLength
      def exec(method, schema, options={})
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
              return exec(method, schema, options)
            end
            msg = "Authentication failed, please retry with correct credentials after resetting the iDrac at #{host}."
          elsif result["stdout"] =~ /Connection failed./ || result["stderr"] =~ /Connection failed./
            if options[:nth_attempt] < 2
              # We have seen sporadic connection failed errors from idrac. Retry a couple times
              options[:nth_attempt] += 1
              logger.info("Connection failed, retrying #{host}...")
              sleep 10
              return exec(method, schema, options)
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

      # Execute a WS-Man Invoke method
      #
      # @param method the method to invoke
      # @param url the instance url to invoke
      # @param options [Hash]
      # @option options [Hash] :params the arguments to be passed as url or invoke parameters
      # @option options [String|Array<String>] :url_params required parameter keys to include in the url
      # @option options [String|Array<String>] :required_params required parameter keys to include as invoke parameters
      # @option options [String|Array<String>] :optional_params optional parameter keys to include as invoke parameters
      # @return [Hash]
      def invoke(method, url, options={})
        params = options.delete(:params) || {}
        raise(ArgumentError, "Invalid parameters: %s" % params) unless params.is_a?(Hash)
        url_params = Array(options.delete(:url_params))
        required_params = Array(options.delete(:required_params))
        optional_params = Array(options.delete(:optional_params))
        all_required = url_params + required_params
        missing_params = all_required.reject { |k| params.include?(k) }
        raise("Missing required parameter(s) for %s: %s" % [method, missing_params.join(", ")]) unless missing_params.empty?

        return_value = options.delete(:return_value)

        props = (required_params + optional_params).inject({}) do |acc, key|
          acc[Parser.param_key(key)] = Parser.wsman_value(key, params[key]) if params[key]
          acc
        end

        unless url_params.empty?
          encoded_arguments = url_params.map do |key|
            "%s=%s" % [URI.escape(Parser.param_key(key)), URI.escape(Parser.wsman_value(key, params[key]))]
          end.join("&")
          uri = URI(url)
          url = "%s%s%s" % [url, uri.query ? "&" : "?", encoded_arguments]
        end

        resp = exec(method, url, :props => props)
        ret = Parser.parse(resp)
        if return_value && !Array(return_value).include?(ret[:return_value])
          raise(ASM::WsMan::ResponseError.new("%s failed" % method, ret))
        end
        ret
      end

      # Execute a WS-Man GET
      #
      # @param url [String] The base URL to fetch
      # @param instance_id [String] The instance id to fetch
      # @return [Hash] the retrieved instance data
      def get(url, instance_id)
        invoke("get", url, :params => {:instance_id => instance_id}, :url_params => :instance_id)
      end

      # Execute a WS-Man Enumerate
      #
      # @param url [String] The base URL to fetch
      def enumerate(url)
        content = exec("enumerate", url)
        resp = Parser.parse_enumeration(content)
        if resp.is_a?(Hash)
          klazz = URI.parse(url).path.split("/").last
          raise(ResponseError.new("%s enumeration failed" % klazz, resp))
        end
        resp
      end
    end
  end
end
