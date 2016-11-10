require "net/ssh"

module ASM
  class Transport
    class IdracResetError < StandardError; end
    class Racadm
      attr_reader :endpoint, :logger

      def initialize(endpoint, log)
        @logger = log
        @endpoint = endpoint
      end

      # Used to reset iDRAC
      #
      # @return [void]
      # @raise [StandardError] the resulting would unable to establish ssh connection or racadm command fails
      def reset_idrac
        logger.debug("Resetting iDrac...")
        Net::SSH.start(@endpoint[:host],
                       @endpoint[:user],
                       :password => @endpoint[:password],
                       :paranoid => Net::SSH::Verifiers::Null.new,
                       :global_known_hosts_file => "/dev/null") do |ssh|
          ssh.exec!("racadm racreset soft") do |_, stream, data|
            logger.debug(data)

            if data.include? "Could not chdir to home directory"
              logger.debug("Warning for message is %s" % data)
            elsif stream == :stderr
              raise IdracResetError
            end
          end
          ssh.close
        end
      end
    end
  end
end
