# frozen_string_literal: true

require "spec_helper"
require "hashie"
require "asm/ipmi/client"

describe ASM::Ipmi::Client do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
  let(:client) {ASM::Ipmi::Client.new(endpoint)}

  describe "#initialize" do
    it "should fail if missing endpoint keys" do
      message = "Missing required endpoint parameter(s): host, user, password"
      expect {ASM::Ipmi::Client.new({})}.to raise_error(message)
    end

    it "should set the logger" do
      client = ASM::Ipmi::Client.new(endpoint, :logger => logger)
      expect(client.logger).to eq(logger)
    end

    it "should add :error to logger if it only responds to :err" do
      puppet_logger = mock(:err => nil)
      client = ASM::Ipmi::Client.new(endpoint, :logger => puppet_logger)
      client.logger.error("Test error")
    end
  end

  describe "#exec" do
    let(:args) do
      ["env", "IPMI_PASSWORD=%s" % endpoint[:password], "ipmitool", "-E",
       "-I", "lanplus", "-H", endpoint[:host], "-U", endpoint[:user]]
    end
    let(:response) {Hashie::Mash.new(:exit_status => 0, :stdout => "rspec-response", :stderr => "")}
    let(:failed_response) {Hashie::Mash.new(:exit_status => 1, :stdout => "Unable to establish IPMI", :stderr => "")}

    it "should execute ipmitool and return stdout" do
      ASM::Util.expects(:run_command_with_args).with(*args, "power", "on").returns(response)
      expect(client.exec("power on")).to eq(response.stdout)
    end

    it "should fail if exit status is non-zero" do
      response.exit_status = 1
      ASM::Util.expects(:run_command_with_args).with(*args, "power", "on").returns(response)
      message = "Failed to execute IPMI command against server rspec-host: %s" % response.to_s
      expect {client.exec("power on")}.to raise_error(message)
    end

    it "should fail if stderr not empty" do
      response.stderr = "Bang!"
      ASM::Util.expects(:run_command_with_args).with(*args, "power", "on").returns(response)
      message = "Failed to execute IPMI command against server rspec-host: %s" % response.to_s
      expect {client.exec("power on")}.to raise_error(message)
    end

    it "should retry if connection failed" do
      ASM::Util.expects(:run_command_with_args).with(*args, "power", "on").returns(response)
      ASM::Util.expects(:run_command_with_args).with(*args, "power", "on").returns(failed_response)
      expect(client.exec("power on")).to eq(response.stdout)
    end

    it "should fail if connection fails three times" do
      ASM::Util.expects(:run_command_with_args).with(*args, "power", "on").returns(failed_response).times(3)
      message = "Unable to establish IPMI, please retry with correct credentials at rspec-host.: %s" % failed_response.to_s
      expect {client.exec("power on")}.to raise_error(message)
    end
  end
end
