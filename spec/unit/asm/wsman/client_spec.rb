require "spec_helper"
require "hashie"
require "asm/wsman/client"

describe ASM::WsMan::Client do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
  let(:client) {ASM::WsMan::Client.new(endpoint)}
  let(:parser) {ASM::WsMan::Parser}

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

  describe "#exec" do
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
      expect(client.exec("enumerate", "rspec-schmea")).to eq(response.stdout)
    end

    it "should execute get" do
      ASM::Util.expects(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "get", "rspec-schmea", *args)
               .returns(response)
      expect(client.exec("get", "rspec-schmea")).to eq(response.stdout)
    end

    it "should execute invoke methods" do
      ASM::Util.expects(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "invoke", "-a", "MyMethod", "rspec-schmea", *args)
               .returns(response)
      expect(client.exec("MyMethod", "rspec-schmea")).to eq(response.stdout)
    end

    it "should fail if exit status is non-zero" do
      response.exit_status = 1
      ASM::Util.expects(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
               .returns(response)
      message = "Failed to execute wsman command against server rspec-host: %s" % response.to_s
      expect {client.exec("enumerate", "rspec-schmea")}.to raise_error(message)
    end

    it "should fail if stderr not empty" do
      response.stderr = "Bang!"
      ASM::Util.expects(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
               .returns(response)
      message = "Failed to execute wsman command against server rspec-host: %s" % response.to_s
      expect {client.exec("enumerate", "rspec-schmea")}.to raise_error(message)
    end

    it "should retry if authentication failed" do
      ASM::Util.stubs(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
               .returns(auth_failed_response, response)
      client.expects(:sleep).with(10)
      expect(client.exec("enumerate", "rspec-schmea")).to eq(response.stdout)
    end

    it "should fail if authentication fails three times" do
      ASM::Util.stubs(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
               .returns(auth_failed_response).times(3)
      client.expects(:sleep).with(10).twice
      message = "Authentication failed, please retry with correct credentials after resetting the iDrac at rspec-host.: %s" % auth_failed_response.to_s
      expect {client.exec("enumerate", "rspec-schmea")}.to raise_error(message)
    end

    it "should retry if connection failed" do
      ASM::Util.stubs(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
               .returns(conn_failed_response, response)
      client.expects(:sleep).with(10)
      expect(client.exec("enumerate", "rspec-schmea")).to eq(response.stdout)
    end

    it "should fail if connection fails three times" do
      ASM::Util.stubs(:run_command_with_args)
               .with("env", "WSMAN_PASS=rspec-password", "wsman", "--non-interactive", "enumerate", "rspec-schmea", *args)
               .returns(conn_failed_response).times(3)
      client.expects(:sleep).with(10).twice
      message = "Connection failed, Couldn't connect to server. Please check IP address credentials for iDrac at rspec-host.: %s" % conn_failed_response.to_s
      expect {client.exec("enumerate", "rspec-schmea")}.to raise_error(message)
    end
  end

  describe "#invoke" do
    let(:url) {"http://rspec/path"}

    it "should fail if missing a required param" do
      message = "Missing required parameter(s) for RspecMethod: foo"
      expect {client.invoke("RspecMethod", url, :params => {}, :required_params => [:foo])}
        .to raise_error(message)
    end

    it "should fail if missing an url param" do
      message = "Missing required parameter(s) for RspecMethod: foo"
      expect {client.invoke("RspecMethod", url, :params => {}, :url_params => [:foo])}
        .to raise_error(message)
    end

    it "should call exec with params and parse the result" do
      client.expects(:exec).with("RspecMethod", url, :props => {"Foo" => "My foo"}).returns("<response />")
      parser.expects(:parse).with("<response />").returns(:return_value => "0")
      expect(client.invoke("RspecMethod", url, :params => {:foo => "My foo"}, :required_params => [:foo]))
        .to eq(:return_value => "0")
    end

    it "should call exec with url params and parse the result" do
      client.expects(:exec).with("RspecMethod", "%s?Foo=My%%20foo" % url, :props => {}).returns("<response />")
      parser.expects(:parse).with("<response />").returns(:return_value => "0")
      expect(client.invoke("RspecMethod", url, :params => {:foo => "My foo"}, :url_params => [:foo]))
        .to eq(:return_value => "0")
    end

    it "should fail if return value does not match" do
      client.expects(:exec).with("RspecMethod", url, :props => {"Foo" => "My foo"}).returns("<response />")
      parser.expects(:parse).with("<response />").returns(:return_value => "2")
      expect {client.invoke("RspecMethod", url, :params => {:foo => "My foo"}, :required_params => [:foo], :return_value => "0") }
        .to raise_error("RspecMethod failed: return_value: 2")
    end

    it "should fail if given a non-nil params that is not a Hash" do
      expect {client.invoke("RspecMethod", url, :params => :bad_value, :required_params => [:foo], :return_value => "0") }
        .to raise_error("Invalid parameters: bad_value")
    end
  end

  describe "#get" do
    it "should call invoke" do
      client.expects(:invoke).with("get", "http://rspec",
                                   :params => {:instance_id => "rspec-instance-id"},
                                   :url_params => :instance_id)
            .returns(:foo => "foo")
      expect(client.get("http://rspec", "rspec-instance-id")).to eq(:foo => "foo")
    end
  end

  describe "#enumerate" do
    let(:url) { "http://rspec/FooCollection" }

    it "should call exec" do
      expected = [{:foo => "foo1"}, {:foo => "foo2"}]
      client.expects(:exec).with("enumerate", url).returns("<response />")
      parser.expects(:parse_enumeration).returns(expected)
      expect(client.enumerate(url)).to eq(expected)
    end

    it "should fail when parse_enumeration returns a hash" do
      client.expects(:exec).with("enumerate", url).returns("<response />")
      parser.expects(:parse_enumeration).returns(:response => "ERROR")
      expect {client.enumerate(url)}.to raise_error("FooCollection enumeration failed: response: ERROR")
    end
  end
end
