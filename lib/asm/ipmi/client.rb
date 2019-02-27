# frozen_string_literal: true

require "asm/util"
require "asm/errors"
require "logger"

module ASM
  class Ipmi
    # IPMI client
    class Client
      attr_reader :endpoint, :logger

      def initialize(endpoint, options={})
        missing_params = %i[host user password].reject { |k| endpoint.include?(k) }
        raise("Missing required endpoint parameter(s): %s" % [missing_params.join(", ")]) unless missing_params.empty?

        @endpoint = endpoint
        @logger = augment_logger(options.delete(:logger) || Logger.new(nil))

        proxy_warn
      end

      # @api private
      def proxy_warn
        logger.warn("ipmi invocations will use the proxy set in http_proxy or https_proxy") if ENV.include?("http_proxy") || ENV.include?("https_proxy")
      end

      # @api private
      # TODO: this is exactly the same as ASM::WsMan::Client#augment_logger
      def augment_logger(logger)
        if !logger.respond_to?(:error) && logger.respond_to?(:err)
          # Puppet logger has most Logger methods, but uses err and warning
          def logger.error(msg)
            err(msg)
          end

          def logger.warn(msg)
            warning(msg)
          end
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

        args = ["IPMI_PASSWORD=#{endpoint[:password]}", "ipmitool", "-E", "-I",
                "lanplus", "-H", host, "-U", endpoint[:user], *command.split]
        logger.debug("Executing env IPMI_PASSWORD=****** %s" % args[1..-1].join(" "))
        result = ASM::Util.run_command_with_args("env", *args)
        logger.debug("Result = #{result}")

        unless result.exit_status.zero? && result.stderr.empty?
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
