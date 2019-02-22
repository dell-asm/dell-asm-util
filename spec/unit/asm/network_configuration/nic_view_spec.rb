require "spec_helper"
require "asm/network_configuration/nic_view"
require "asm/network_configuration/nic_port"

describe ASM::NetworkConfiguration::NicView do
  let(:logger) { double(:debug => nil, :warn => nil, :info => nil) }

  def nic_view(fqdd, logger=nil)
    ASM::NetworkConfiguration::NicView.new(fqdd, logger)
  end

  describe "#initialize" do
    # Blade examples:
    #
    # NIC.Integrated.1-1-1: 24:B6:FD:F9:FC:42
    # NIC.Integrated.1-1-2: 24:B6:FD:F9:FC:46
    # NIC.Integrated.1-1-3: 24:B6:FD:F9:FC:4A
    # NIC.Integrated.1-1-4: 24:B6:FD:F9:FC:4E
    # NIC.Integrated.1-2-1: 24:B6:FD:F9:FC:44
    # NIC.Integrated.1-2-2: 24:B6:FD:F9:FC:48
    # NIC.Integrated.1-2-3: 24:B6:FD:F9:FC:4C
    # NIC.Integrated.1-2-4: 24:B6:FD:F9:FC:50
    # NIC.Mezzanine.2B-1-1: 00:10:18:DC:C4:80
    # NIC.Mezzanine.2B-1-2: 00:10:18:DC:C4:84
    # NIC.Mezzanine.2B-1-3: 00:10:18:DC:C4:88
    # NIC.Mezzanine.2B-1-4: 00:10:18:DC:C4:8C
    # NIC.Mezzanine.2B-2-1: 00:10:18:DC:C4:82
    # NIC.Mezzanine.2B-2-2: 00:10:18:DC:C4:86
    # NIC.Mezzanine.2B-2-3: 00:10:18:DC:C4:8A
    # NIC.Mezzanine.2B-2-4: 00:10:18:DC:C4:8E
    #
    # Intel blade examples:
    #
    # NIC.Integrated.1-1-1: 24:B6:FD:F9:FC:42
    # NIC.Integrated.1-2-1: 24:B6:FD:F9:FC:44
    # NIC.Mezzanine.2B-1:   00:10:18:DC:C4:80
    # NIC.Mezzanine.2B-2:   00:10:18:DC:C4:82
    # NIC.Mezzanine.2C-1:   00:10:18:DC:C4:80
    # NIC.Mezzanine.2C-2:   00:10:18:DC:C4:82
    #
    # Rack examples:
    #
    # NIC.Slot.2-1-1: 00:0A:F7:06:88:50
    # NIC.Slot.2-1-2: 00:0A:F7:06:88:54
    # NIC.Slot.2-1-3: 00:0A:F7:06:88:58
    # NIC.Slot.2-1-4: 00:0A:F7:06:88:5C
    # NIC.Slot.2-2-1: 00:0A:F7:06:88:52
    # NIC.Slot.2-2-2: 00:0A:F7:06:88:56
    # NIC.Slot.2-2-3: 00:0A:F7:06:88:5A
    # NIC.Slot.2-2-4: 00:0A:F7:06:88:5E

    it "should parse NIC.Embedded.1-1-1" do
      fqdd = nic_view("NIC.Embedded.1-1-1")
      expect(fqdd.type).to eq("Embedded")
      expect(fqdd.card).to eq("1")
      expect(fqdd.port).to eq("1")
      expect(fqdd.partition_no).to eq("1")
    end

    it "should parse NIC.Embedded.2-1-1" do
      fqdd = nic_view("NIC.Embedded.2-1-1")
      expect(fqdd.type).to eq("Embedded")
      expect(fqdd.card).to eq("1")
      expect(fqdd.port).to eq("2")
      expect(fqdd.partition_no).to eq("1")
    end

    it "should parse NIC.Integrated.1-1-1" do
      fqdd = nic_view("NIC.Integrated.1-1-1")
      expect(fqdd.type).to eq("Integrated")
      expect(fqdd.card).to eq("1")
      expect(fqdd.port).to eq("1")
      expect(fqdd.partition_no).to eq("1")
    end

    it "should parse NIC.Integrated.1-2-3" do
      fqdd = nic_view("NIC.Integrated.1-2-3")
      expect(fqdd.type).to eq("Integrated")
      expect(fqdd.card).to eq("1")
      expect(fqdd.port).to eq("2")
      expect(fqdd.partition_no).to eq("3")
    end

    it "should parse NIC.Mezzanine.2B-2-4" do
      fqdd = nic_view("NIC.Mezzanine.2B-2-4")
      expect(fqdd.type).to eq("Mezzanine")
      expect(fqdd.card).to eq("2")
      expect(fqdd.fabric).to eq("B")
      expect(fqdd.port).to eq("2")
      expect(fqdd.partition_no).to eq("4")
    end

    it "should be confused by NIC.Mezzanine.2C-2-4" do
      logger = mock("NIC.Mezzanine.2C-2-4")
      logger.expects(:warn)
      fqdd = nic_view("NIC.Mezzanine.2C-2-4", logger)
      expect(fqdd.type).to eq("Mezzanine")
      expect(fqdd.card).to eq("2")
      expect(fqdd.fabric).to eq("C")
      expect(fqdd.port).to eq("2")
      expect(fqdd.partition_no).to eq("4")
    end

    it "should parse NIC.Mezzanine.2B-2" do
      fqdd = nic_view("NIC.Mezzanine.2B-2")
      expect(fqdd.type).to eq("Mezzanine")
      expect(fqdd.card).to eq("2")
      expect(fqdd.fabric).to eq("B")
      expect(fqdd.port).to eq("2")
      expect(fqdd.partition_no).to eq("1")
    end

    it "should parse rack fqdd in port 1" do
      fqdd = nic_view("NIC.Slot.2-1-1")
      expect(fqdd.type).to eq("Slot")
      expect(fqdd.card).to eq("2")
      expect(fqdd.port).to eq("1")
      expect(fqdd.partition_no).to eq("1")
    end

    it "should parse rack fqdd in port 2" do
      fqdd = nic_view("NIC.Slot.2-2-3")
      expect(fqdd.type).to eq("Slot")
      expect(fqdd.card).to eq("2")
      expect(fqdd.port).to eq("2")
      expect(fqdd.partition_no).to eq("3")
    end
  end

  describe "#card_prefix" do
    it "should include type and card" do
      expect(nic_view("NIC.Integrated.1-1-1").card_prefix).to eq("NIC.Integrated.1")
    end

    it "should include fabric" do
      expect(nic_view("NIC.Mezzanine.1C-1-1").card_prefix).to eq("NIC.Mezzanine.1C")
    end
  end

  describe "#nic_slot_id" do
    it "should return correct slot" do
      expect(nic_view("NIC.Slot.2-1-1").nic_slot_id).to eq("2")
    end

    it "should return slot id as 0 for Integrated nic type" do
      expect(nic_view("NIC.Integrated.1-1-1").nic_slot_id).to eq("0")
    end

    it "should return slot id as 0 for Embedded nic type" do
      expect(nic_view("NIC.Embedded.1-1-1").nic_slot_id).to eq("0")
    end
  end

  describe "#<=>" do
    it "should show same FQDDs as equal" do
      fqdd1 = "NIC.Integrated.1-1-1"
      fqdd2 = "NIC.Integrated.1-1-1"
      expect(nic_view(fqdd1) <=> nic_view(fqdd2)).to eq(0)
    end

    it "should order by type" do
      expect(nic_view("NIC.Integrated.1-1-1") <=> nic_view("NIC.Mezzanine.1B-1-1")).to eq(-1)
    end

    it "should order by card" do
      expect(nic_view("NIC.Slot.2-1-1") <=> nic_view("NIC.Slot.1-1-1")).to eq(1)
    end

    it "should order by fabric" do
      expect(nic_view("NIC.Mezzanine.1B-1-1") <=> nic_view("NIC.Mezzanine.1C-1-1")).to eq(-1)
    end

    it "should order by port" do
      expect(nic_view("NIC.Mezzanine.1B-2-1") <=> nic_view("NIC.Mezzanine.1B-1-1")).to eq(1)
    end

    it "should order by partition" do
      expect(nic_view("NIC.Mezzanine.1B-1-4") <=> nic_view("NIC.Mezzanine.1B-1-1")).to eq(1)
    end
  end
end
