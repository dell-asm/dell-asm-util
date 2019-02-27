# frozen_string_literal: true

module ASM
  class NetworkConfiguration
    # NicType provides overview information about a single logical NIC
    #
    # At the WS-Man level via DCIM_NicView, NIC information is
    # reported from a per-port and/or per-partition point of
    # view. This class ties the individual NIC views together into a
    # single logical NIC.
    class NicType
      attr_accessor(:nictype)
      attr_accessor(:ports)

      # Creates a new ASM::NicType instance from a nictype string.
      #
      # Current expected nictype values are "2x10Gb", "4x10Gb", "2x10Gb,2x1Gb" and "2x25Gb".
      # Older templates may also send just "2" or "4", in which case they should
      # be treated as referring to 10Gb ports.
      #
      # @param nictype [String]
      # @return [ASM::NicType]
      def initialize(nictype)
        @ports = nictype.split(",").map(&:strip).map do |desc|
          n, type = desc.split("x")
          type ||= "10Gb"
          Array.new(n.to_i, type)
        end.flatten
        @nictype = nictype
        @nictype = "2x10Gb" if nictype == "2"
        @nictype = "4x10Gb" if nictype == "4"
      end

      # Return the number ports that can be configured
      #
      # Currently 1Gb NICs are not supported.
      #
      # @return [Fixnum]
      def n_usable_ports
        @n_usable_ports ||= @ports.find_all { |port| port != "1Gb" }.size
      end

      # Return the number of ports
      #
      # @return [Fixnum] number of ports
      def n_ports
        @ports.size
      end

      # Returns the number of partitions available for usable ports on this NicType.
      #
      # @return [Fixnum]
      def n_partitions
        raise("NIC type %s does not support partitioning" % @nictype) unless n_usable_ports.positive?

        if n_usable_ports == 2 && n_ports == 2
          4
        else
          2
        end
      end

      def ==(other)
        @ports == other.ports
      end

      def to_s
        @nictype
      end
    end
  end
end
