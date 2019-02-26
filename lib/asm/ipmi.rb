# frozen_string_literal: true

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
      if power_state == :off
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
    # @return [Symbol] :on or :off
    def power_state
      response = client.exec("power status")
      raise(ASM::Error, "Invalid IPMI power status response: %s" % response) unless response =~ /Chassis Power is\s+(\S+)/m

      state = $1.downcase
      raise(ASM::Error, "Invalid IPMI power state %s; full response: %s" % [state, response]) unless %w[on off].include?(state)

      logger.debug("Current power status: #{response}")
      state.to_sym
    end

    # @deprecated Use {#power_state} instead
    def self.get_power_status(endpoint, logger=nil)
      ASM::Ipmi.new(endpoint, :logger => logger).power_state.to_s
    end

    # Power the server on
    #
    # This is a no-op if the server is already on.
    #
    # @return [void]
    def power_on
      if power_state == :on
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
      if power_state == :off
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
