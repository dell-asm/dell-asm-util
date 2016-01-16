require "logger"

module ASM
  class NetworkConfiguration
    # NicPort encapsulates information about a server NIC port such as link speed
    # and the number of NPAR partitions available on that port.
    class NicPort
      # The iDrac NICView LinkSpeed values
      LINK_SPEEDS = ["Unknown", "10 Mbps", "100 Mbps", "1000 Mbps", "2.5 Gbps", "10 Gbps", "20 Gbps", "40 Gbps", "100 Gbps"].freeze

      attr_reader :link_speed, :n_ports, :partitions, :logger

      # Create a NicPort
      #
      # @param nic_view [Array[NicView]] The NIC views for each partition
      # @param logger [Logger] logger to use for log messages
      # @return [NicPort]
      def initialize(partitions, n_ports, logger=nil)
        raise(ArgumentError, "At least one NicView required to create a NicPort") unless partitions.size > 0
        @partitions = partitions
        @n_ports = n_ports
        @logger = logger || Logger.new(nil)

        @model ||= nic_view["ProductName"]
        @link_speed = model_speed
        @link_speed ||= LINK_SPEEDS[Integer(nic_view["LinkSpeed"])] if nic_view["LinkSpeed"]
        @link_speed ||= LINK_SPEEDS[0]
      end

      def nic_view
        partitions.first
      end

      # The vendor for the NIC port
      #
      # Currently only :qlogic and :intel vendors are recognized
      #
      # @return [Symbol|Void] the vendor or nil if none recognized
      def vendor
        nic_view.vendor
      end

      # The product name of the NIC port
      #
      # @return [String|Void] the product name or nil if none recognized
      def product
        nic_view.product
      end

      # The port number
      #
      # @return [FixNum] the port number
      def port
        Integer(nic_view.port)
      end

      # Whether the NIC port belongs to a Broadcom / QLogic 57800 NIC
      #
      # @return [Boolean]
      def is_qlogic_57800?
        vendor == :qlogic && product =~ /(^|\D)57800(|\D|$)/ && n_ports == 4
      end

      # Whether the NIC port belongs to a Broadcom / QLogic 57810 NIC
      #
      # @return [Boolean]
      def is_qlogic_57810?
        vendor == :qlogic && product =~ /(^|\D)57810(\D|$)/ && n_ports == 2
      end

      # Whether the NIC port belongs to a Broadcom / QLogic 57840 NIC
      #
      # @return [Boolean]
      def is_qlogic_57840?
        vendor == :qlogic && product =~ /(^|\D)57840(\D|$)/ && n_ports == 4
      end

      # Whether the NIC port belongs to a 2x10Gb Intel X520 NIC
      #
      # Note that there appear to be many X520 variants. This method only returns
      # true for 2x10Gb X520 NICs
      #
      # @return [Boolean]
      def is_intel_x520?
        vendor == :intel && product =~ /x520(\D|$)/i && n_ports == 2
      end

      # The NIC port speed as determined by NIC vendor and model information
      #
      # Currently recognizes speed values for Broadcom 57800, 57810 and 57840
      # and 2x10Gb Intel X520 NICs. Returns nil for all other NIC models.
      #
      # @return [String|Void] The link speed for recognized NIC models, nil otherwise.
      def model_speed
        return "10 Gbps" if is_qlogic_57810?
        return "10 Gbps" if is_qlogic_57840?

        # Broadcom / QLogic 57800 is a 2x10Gb, 2x1Gb NIC
        return "10 Gbps" if is_qlogic_57800? && port.between?(1, 2)
        return "1000 Mbps" if is_qlogic_57800? && port.between?(3, 4)

        return "10 Gbps" if is_intel_x520?
        nil
      end

      # The number of NPAR partitions possible on the port
      #
      # Currently recognizes NPAR values for Broadcom 57800, 57810 and 57840 NICs.
      # All other NICs report a value of 1.
      #
      # @return [FixNum] the maximum number of NPAR partitions for the port
      def n_partitions
        return 4 if is_qlogic_57810?
        return 2 if is_qlogic_57840?
        return 2 if is_qlogic_57800? && port.between?(1, 2)
        1
      end

      def to_s
        "#<ASM::NetworkConfiguration::NicPort %s product: %s port: %d>" % [nic_view.fqdd, product, port]
      end

      def <=>(other)
        nic_view <=> other.nic_view
      end
    end
  end
end
