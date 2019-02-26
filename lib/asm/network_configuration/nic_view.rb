# frozen_string_literal: true

require "hashie"

module ASM
  class NetworkConfiguration
    # Wrapper class for DCIM_NICView
    class NicView
      include Comparable

      attr_reader :fqdd, :type, :card, :port, :partition_no, :fabric, :slot

      def initialize(fqdd, logger=nil)
        if fqdd.is_a?(Hash)
          @raw_nic_view = fqdd
          fqdd = fqdd["FQDD"]
        end
        @raw_nic_view ||= {"FQDD" => fqdd}
        parse_fqdd(fqdd, logger)
      end

      # Create a new NicInfo based off self but with a different partition
      def create_with_partition(partition)
        NicView.new(fqdd.gsub(/[-]\d+$/, "-#{partition}"))
      end

      # Return raw NIC view values
      #
      # @param key [String] NIC view key
      # @return [String] NIC view value
      def [](key)
        @raw_nic_view[key]
      end

      def card_to_fabric(card)
        ["A", "B", "C"][card.to_i - 1]
      end

      def parse_fqdd(fqdd, logger)
        # Expected format: NIC.Mezzanine.2B-1-1
        raise(ArgumentError, "Invalid NIC FQDD: %s" % fqdd) unless fqdd =~ /^NIC[.]([^.]*)[.](\d+[A-Z]?)-(\d+)(-([\d+]))?$/

        @fqdd = fqdd
        @type = $1
        @card = $2
        @port = $3
        @partition_no = $5
        @partition_no = "1" if @partition_no.nil?
        @slot = nic_slot_id
        if @card =~ /([0-9])([A-Z])/
          orig_card = @card
          @card = $1
          @fabric = $2
          expected_fabric = card_to_fabric(orig_card)
          logger&.warn("Mismatched fabric information for #{orig_card}: #{@fabric} versus #{expected_fabric}") if @fabric != expected_fabric
        elsif @type == "Embedded"
          @port = @card
          @card = "1"
        end
      end

      def self.empty_mac?(mac)
        mac.nil? || mac.empty? || mac == "00:00:00:00:00:00"
      end

      # The current mac address
      #
      # @return [String]
      def mac_address
        if NicView.empty_mac?(self["CurrentMACAddress"])
          self["PermanentMACAddress"]
        elsif self["PermanentMACAddress"]
          self["CurrentMACAddress"]
        end
      end

      # The vendor for the NIC port
      #
      # Currently only :qlogic and :intel vendors are recognized
      #
      # @return [Symbol|Void] the vendor or nil if none recognized
      def vendor
        return :qlogic if self["VendorName"] =~ /qlogic|broadcom/i
        return :qlogic if self["PCIVendorID"] == "14e4"

        return :mellanox if self["VendorName"] =~ /mellanox/i
        return :mellanox if self["PCIVendorID"] == "15b3"

        return :intel if self["VendorName"] =~ /intel/i

        :intel if self["PCIVendorID"] == "8086" # have seen cases where VendorName not populated
      end

      def pci_device_id
        self["PCIDeviceID"]
      end

      # The product name of the NIC port
      #
      # @return [String|Void] the product name or nil if none recognized
      def product
        self["ProductName"]
      end

      def card_prefix
        "NIC.%s.%s%s" % [type, card, fabric]
      end

      # Returns the nic slot id based on fqdd
      #
      # returns 0 for Integrated and Embedded nic types
      #
      # @return [String]
      def nic_slot_id
        return "0" if fqdd.include?("NIC.Integrated") || fqdd.include?("NIC.Embedded")

        fqdd.scan(/NIC.Slot.(\d+).*/).flatten.first
      end

      def to_s
        "#<ASM::NetworkConfiguration::NicInfo fqdd: %s>" % fqdd
      end

      def <=>(other)
        %i[type card fabric port partition_no].each do |method|
          this = send(method)
          this = Integer(this) if %i[card port partition_no].include?(method)
          that = other.send(method)
          that = Integer(that) if %i[card port partition_no].include?(method)
          return this <=> that unless (this <=> that).zero?
        end
        0
      end
    end
  end
end
