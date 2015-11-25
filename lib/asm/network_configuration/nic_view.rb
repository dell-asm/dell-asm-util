require "hashie"

module ASM
  class NetworkConfiguration
    class NicView
      include Comparable

      attr_accessor :nic_view

      def initialize(fqdd, logger = nil)
        if fqdd.is_a?(Hash)
          @nic_view = fqdd
          fqdd = fqdd["FQDD"]
        end
        @mash = parse_fqdd(fqdd, logger)
      end

      # Create a new NicInfo based off self but with a different partition
      def create_with_partition(partition)
        NicView.new(@mash.fqdd.gsub(/[-]\d+$/, "-#{partition}"))
      end

      # Forward methods we don't define directly to the mash
      def method_missing(sym, *args, &block)
        @mash.send(sym, *args, &block)
      end

      def card_to_fabric(card)
        ['A', 'B', 'C'][card.to_i - 1]
      end

      def parse_fqdd(fqdd, logger)
        ret = Hashie::Mash.new
        # Expected format: NIC.Mezzanine.2B-1-1
        ret.fqdd = fqdd
        (_, ret.type, port_info) = ret.fqdd.split('.')
        (ret.card, ret.port, ret.partition_no) = port_info.split('-')
        ret.partition_no = '1' if ret.partition_no.nil?
        if ret.card =~ /([0-9])([A-Z])/
          orig_card = ret.card
          ret.card = $1
          ret.fabric = $2
          expected_fabric = card_to_fabric(orig_card)
          if ret.fabric != expected_fabric
            logger.warn("Mismatched fabric information for #{orig_card}: #{ret.fabric} versus #{expected_fabric}") if logger
          end
        else
          if ret.type == 'Embedded'
            ret.port = ret.card
            ret.card = '1'
          end
          ret.fabric = card_to_fabric(ret.card)
        end
        ret
      end

      def card_prefix
        "NIC.#{@mash.type}.#{@mash.card}"
      end

      def to_s
        "#<ASM::NetworkConfiguration::NicInfo fqdd: %s>" % fqdd
      end

      def <=>(other)
        ret = self.type <=> other.type
        if ret == 0
          ret = Integer(self.card) <=> Integer(other.card)
          if ret == 0
            ret = Integer(self.port) <=> Integer(other.port)
            if ret == 0
              ret = Integer(self.partition_no) <=> Integer(other.partition_no)
            end
          end
        end
        ret
      end
    end
  end
end
