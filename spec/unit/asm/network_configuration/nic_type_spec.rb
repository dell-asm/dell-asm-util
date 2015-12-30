require "spec_helper"
require "asm/network_configuration"

describe ASM::NetworkConfiguration::NicType do
  before do
    SpecHelper.init_i18n
  end

  describe "#ASM::NicType" do
    describe "#ports" do
      it "should parse 2x10Gb" do
        expect(ASM::NetworkConfiguration::NicType.new("2x10Gb").ports)
          .to eq(["10Gb", "10Gb"])
      end

      it "should parse 4x10Gb" do
        expect(ASM::NetworkConfiguration::NicType.new("4x10Gb").ports)
          .to eq(["10Gb", "10Gb", "10Gb", "10Gb"])
      end

      it "should parse 2x10Gb,2x1Gb" do
        expect(ASM::NetworkConfiguration::NicType.new("2x10Gb,2x1Gb").ports)
          .to eq(["10Gb", "10Gb", "1Gb", "1Gb"])
      end

      it "should parse 2" do
        expect(ASM::NetworkConfiguration::NicType.new("2").ports)
          .to eq(["10Gb", "10Gb"])
      end

      it "should parse 4" do
        expect(ASM::NetworkConfiguration::NicType.new("4").ports)
          .to eq(["10Gb", "10Gb", "10Gb", "10Gb"])
      end

      it "should support exact equality" do
        expect(ASM::NetworkConfiguration::NicType.new("4x10Gb")).to eq(ASM::NetworkConfiguration::NicType.new("4x10Gb"))
      end

      it "should support logical equality" do
        expect(ASM::NetworkConfiguration::NicType.new("4")).to eq(ASM::NetworkConfiguration::NicType.new("4x10Gb"))
      end
    end

    describe "#n_partitions" do
      it "should return 4 for 2x10Gb" do
        expect(ASM::NetworkConfiguration::NicType.new("2x10Gb").n_partitions).to eq(4)
      end

      it "should return 2 for 2x10Gb,2x1Gb" do
        expect(ASM::NetworkConfiguration::NicType.new("2x10Gb,2x1Gb").n_partitions).to eq(2)
      end

      it "should return 2 for 4x10Gb" do
        expect(ASM::NetworkConfiguration::NicType.new("4x10Gb").n_partitions).to eq(2)
      end

      it "should fail if not 10Gb NICs" do
        expect { ASM::NetworkConfiguration::NicType.new("4x1Gb").n_partitions }
          .to raise_error("NICs without 10Gb ports cannot be partitioned")
      end
    end
  end
end
