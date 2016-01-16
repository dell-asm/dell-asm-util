require "asm/ipmi/client"

module ASM
  # IPMI client. Wraps the ipmitool CLI utility.
  class Ipmi
    attr_reader :client

    # Create an IPMI client
    #
    # @param endpoint [Hash]
    # @option endpoint [String] :host the host
    # @option endpoint [String] :user the username
    # @option options [String] :password the password
    # @param options [Hash]
    # @option options [Logger] :logger logger to use.
    # @return [Ipmi]
    # @raise [StandardError] if missing endpoint parameters
    def initialize(endpoint, options={})
      @client = Client.new(endpoint, options)
    end

    def logger
      client.logger
    end

    def host
      client.host
    end

    # Reboot the server.
    #
    # The server will be power cycled if it is already on, or powered on otherwise.
    #
    # @return [void]
    def reboot
      if get_power_status == "off"
        logger.info("Server is powered-off. Need to power-on the server")
        client.exec("power on")
      else
        client.exec("power cycle")
      end
      nil
    end

    # @deprecated Use {#reboot} instead
    def self.reboot(endpoint, logger=nil)
      ASM::Ipmi.new(endpoint, :logger => logger).reboot
    end

    # Get server power status
    #
    # @return [String] "on" if the server is on or "off" if it is off.
    def get_power_status # rubocop:disable Style/AccessorMethodName
      power_status = client.exec("power status")
      power_status = power_status.scan(/Chassis Power is\s+(\S+)$/m).flatten.first.strip
      logger.debug("Current power status: #{power_status}") if logger
      power_status
    end

    # @deprecated Use {#get_power_status} instead
    def self.get_power_status(endpoint, logger=nil)
      ASM::Ipmi.new(endpoint, :logger => logger).get_power_status
    end

    # Power the server on
    #
    # This is a no-op if the server is already on.
    #
    # @return [void]
    def power_on
      if get_power_status == "on"
        logger.info("Server is already powered-on.")
        return
      end
      client.exec("power on")
      nil
    end

    # @deprecated Use {#power_on} instead
    def self.power_on(endpoint, logger=nil)
      ASM::Ipmi.new(endpoint, :logger => logger).power_on
    end

    # Power the server off
    #
    # This is a no-op if the server is already off.
    #
    # @return [void]
    def power_off
      if get_power_status == "off"
        logger.info("Server is already powered-off.")
        return true
      end
      client.exec("power off")
      nil
    end

    # @deprecated Use {#power_off} instead
    def self.power_off(endpoint, logger=nil)
      ASM::Ipmi.new(endpoint, :logger => logger).power_off
    end
  end
end
