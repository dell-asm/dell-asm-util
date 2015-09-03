module ASM
  class NetworkConfiguration
    class NicInfo
      def initialize(fqdd, logger = nil)
        @mash = parse_fqdd(fqdd, logger)
      end

      # Create a new NicInfo based off self but with a different partition
      def create_with_partition(partition)
        NicInfo.new(@mash.fqdd.gsub(/[-]\d+$/, "-#{partition}"))
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
    end
  end
end
