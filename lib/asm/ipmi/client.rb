require "asm/util"
require "asm/errors"
require "logger"

module ASM
  class Ipmi
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
          logger.warn("ipmi invocations will use the proxy set in http_proxy or https_proxy")
        end
      end

      # @api private
      # TODO: this is exactly the same as ASM::WsMan::Client#augment_logger
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

      # Execute the ipmitool CLI cient
      #
      # Will automatically retry in the case of connection errors.
      #
      # @param command the IPMI command.
      # @param options [Hash]
      # @option options [FixNum] :nth_attempt used internally to allow recursive retry
      # @return [String]
      def exec(command, options={})
        options[:nth_attempt] ||= 0

        base_cmd = "ipmitool"
        args = ["-I", "lanplus", "-H", host,
                "-U", endpoint[:user], "-P", endpoint[:password], *command.split]
        masked_args = args.dup
        masked_args[args.find_index("-P") + 1] = "******"
        logger.debug("Executing ipmitool #{masked_args.join(' ')}")
        # TODO: if ipmitool has a way to specify password not as an argument, should use that
        result = ASM::Util.run_command_with_args(base_cmd, *args)
        logger.debug("Result = #{result}")

        unless result.exit_status == 0 && result.stderr.empty?
          if result["stdout"] =~ /Unable to establish IPMI/
            if options[:nth_attempt] < 2
              options[:nth_attempt] += 1
              logger.info("Unable to access IPMI interface, retrying %s..." % host)
              return exec(command, :nth_attempt => options[:nth_attempt])
            end
            msg = "Unable to establish IPMI, please retry with correct credentials at %s." % host
          else
            msg = "Failed to execute IPMI command against server %s" % host
          end
          logger.error(msg)
          raise(ASM::Error, "#{msg}: #{result}")
        end

        result["stdout"]
      end
    end
  end
end
