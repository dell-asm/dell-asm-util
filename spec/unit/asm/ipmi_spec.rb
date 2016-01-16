require "spec_helper"
require "asm/ipmi"

describe ASM::Ipmi do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
  let(:ipmi) { ASM::Ipmi.new(endpoint, :logger => logger) }
  let(:client) { ipmi.client }

  describe "#reboot" do
    it "should power on if server is off" do
      ipmi.expects(:get_power_status).returns("off")
      client.expects(:exec).with("power on")
      ipmi.reboot
    end

    it "should power cycle otherwise" do
      ipmi.expects(:get_power_status).returns("on")
      client.expects(:exec).with("power cycle")
      ipmi.reboot
    end
  end

  describe "#get_power_status" do
    it "should retrieve power off" do
      client.expects(:exec).with("power status").returns("Chassis Power is off")
      expect(ipmi.get_power_status).to eq("off")
    end

    it "should retrieve power on" do
      client.expects(:exec).with("power status").returns("Chassis Power is on")
      expect(ipmi.get_power_status).to eq("on")
    end

    it "should fail on unexpected response" do
      # TOOD: should raise an error!
    end
  end

  describe "#power_on" do
    it "should do nothing if power already on" do
      ipmi.expects(:get_power_status).returns("on")
      client.expects(:exec).never
      ipmi.power_on
    end

    it "should power on if power is off" do
      ipmi.expects(:get_power_status).returns("off")
      client.expects(:exec).with("power on")
      ipmi.power_on
    end
  end

  describe "#power_off" do
    it "should do nothing if power already off" do
      ipmi.expects(:get_power_status).returns("off")
      client.expects(:exec).never
      ipmi.power_off
    end

    it "should power on if power is off" do
      ipmi.expects(:get_power_status).returns("on")
      client.expects(:exec).with("power off")
      ipmi.power_off
    end
  end
end
