module ASM
  class NetworkConfiguration
    class NicType
      attr_accessor(:nictype)
      attr_accessor(:ports)

      # Creates a new ASM::NicType instance from a nictype string.
      #
      # Current expected nictype values are "2x10Gb", "4x10Gb" and "2x10Gb,2x1Gb".
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

      def n_10gb_ports
        @n_10gb_ports ||= @ports.find_all { |port| port == "10Gb" }.size
      end

      # Return the number of ports
      #
      # @return [Fixnum] number of ports
      def n_ports
        @ports.size
      end

      # Returns the number of partitions available for a 10Gb port on this NicType.
      #
      # @return [Fixnum] The number of partitions available per 10Gb port
      def n_partitions
        raise("NICs without 10Gb ports cannot be partitioned") unless n_10gb_ports > 0

        if n_10gb_ports == 2 && n_ports == 2
          4
        else
          2
        end
      end

      def ==(other)
        @ports == other.ports
      end

      def to_s
        "NicType<%s>" % @nictype
      end
    end
  end
end
