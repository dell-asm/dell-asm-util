require "spec_helper"
require "hashie"
require "asm/wsman/client"

describe ASM::WsMan::Client do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }

  describe "#initialize" do
    it "should fail if missing endpoint keys" do
      message = "Missing required endpoint parameter(s): host, user, password"
      expect {ASM::WsMan::Client.new({})}.to raise_error(message)
    end

    it "should set the logger" do
      client = ASM::WsMan::Client.new(endpoint, :logger => logger)
      expect(client.logger).to eq(logger)
    end

    it "should add :error to logger if it only responds to :err" do
      puppet_logger = mock(:err => nil)
      client = ASM::WsMan::Client.new(endpoint, :logger => puppet_logger)
      client.logger.error("Test error")
    end
  end

  describe "#invoke" do
    let(:client) {ASM::WsMan::Client.new(endpoint)}
    let(:args) do
      ["-h", endpoint[:host], "-V", "-v", "-c", "dummy.cert", "-P", "443",
       "-u", endpoint[:user], "-j", "utf-8", "-m", "256", "-y", "basic", "--transport-timeout=300"]
    end
    let(:response) {Hashie::Mash.new(:exit_status => 0, :stdout => "rspec-response", :stderr => "")}
    let(:auth_failed_response) {Hashie::Mash.new(:exit_status => 1, :stdout => "Authentication failed", :stderr => "")}
    let(:conn_failed_response) {Hashie::Mash.new(:exit_status => 1, :stdout => "Connection failed.", :stderr => "")}

    it "execute enumerate" do
      ASM::Util.expects(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(response)
      expect(client.invoke("enumerate", "rspec-schmea")).to eq(response.stdout)
    end

    it "should execute get" do
      ASM::Util.expects(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "get", "rspec-schmea", *args)
        .returns(response)
      expect(client.invoke("get", "rspec-schmea")).to eq(response.stdout)
    end

    it "should execute invoke methods" do
      ASM::Util.expects(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "invoke", "-a", "MyMethod", "rspec-schmea", *args)
        .returns(response)
      expect(client.invoke("MyMethod", "rspec-schmea")).to eq(response.stdout)
    end

    it "should fail if exit status is non-zero" do
      response.exit_status = 1
      ASM::Util.expects(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(response)
      message = "Failed to execute wsman command against server rspec-host: %s" % response
      expect {client.invoke("enumerate", "rspec-schmea")}.to raise_error(message)
    end

    it "should fail if stderr not empty" do
      response.stderr = "Bang!"
      ASM::Util.expects(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(response)
      message = "Failed to execute wsman command against server rspec-host: %s" % response
      expect {client.invoke("enumerate", "rspec-schmea")}.to raise_error(message)
    end

    it "should retry if authentication failed" do
      ASM::Util.stubs(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(auth_failed_response, response)
      client.expects(:sleep).with(10)
      expect(client.invoke("enumerate", "rspec-schmea")).to eq(response.stdout)
    end

    it "should fail if authentication fails three times" do
      ASM::Util.stubs(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(auth_failed_response).times(3)
      client.expects(:sleep).with(10).twice
      message = "Authentication failed, please retry with correct credentials after resetting the iDrac at rspec-host.: %s" % auth_failed_response
      expect {client.invoke("enumerate", "rspec-schmea")}.to raise_error(message)
    end

    it "should retry if connection failed" do
      ASM::Util.stubs(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(conn_failed_response, response)
      client.expects(:sleep).with(10)
      expect(client.invoke("enumerate", "rspec-schmea")).to eq(response.stdout)
    end

    it "should fail if connection fails three times" do
      ASM::Util.stubs(:run_command_with_args)
        .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
        .returns(conn_failed_response).times(3)
      client.expects(:sleep).with(10).twice
      message = "Connection failed, Couldn't connect to server. Please check IP address credentials for iDrac at rspec-host.: %s" % conn_failed_response
      expect {client.invoke("enumerate", "rspec-schmea")}.to raise_error(message)
    end
  end
end
