require "asm/racadm/transport"

module ASM
  class IdracResetError < Exception; end
  class Racadm
    attr_reader :transport, :endpoint, :logger

    def initialize(endpoint, options={})
      @logger = ASM::Util.augment_logger(options.delete(:logger) || Logger.new(nil))
      @transport = ASM::Racadm::Transport.new(endpoint, options)
      @endpoint = endpoint
    end

    def client
      transport.client
    end

    def reset_idrac
      logger.info("Resetting IDrac...")

      client.exec "racadm racreset soft" do |_, stream, data|
        logger.debug(data)

        # Issue warning for the message 'Could not chdir to home directory /flash/data0/home/root: No such file or directory' else raise error
        if data.include? "Could not chdir to home directory"
          logger.warning "Warning for message - #{data}"
        elsif stream == :stderr
          raise IdracResetError
        end
      end
      client.close
    end
  end
end
