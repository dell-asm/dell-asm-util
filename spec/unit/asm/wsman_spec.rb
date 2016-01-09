require "spec_helper"
require "asm/wsman"

describe ASM::WsMan do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }

  describe "when parsing nicview with disabled 57800 and dual-port slot nic" do
    before do
      # NOTE: this data is from a rack with a dual-port slot nic and a quad-port
      # integrated nic. Note the quad-port nic isn't showing any current or
      # permanent mac addresses, so it isn't found in the get_mac_addresses call
      file_name = File.join(File.dirname(__FILE__), "..", "..",
                            "fixtures", "wsman", "nic_view.xml")
      @nic_view_response = File.read(file_name)
    end

    it "should find current macs" do
      ASM::WsMan.stubs(:invoke).returns(@nic_view_response)
      macs = ASM::WsMan.get_mac_addresses(nil, nil)
      macs.should == {"NIC.Slot.2-1-1" => "00:0A:F7:06:9D:C0",
                      "NIC.Slot.2-1-2" => "00:0A:F7:06:9D:C4",
                      "NIC.Slot.2-1-3" => "00:0A:F7:06:9D:C8",
                      "NIC.Slot.2-1-4" => "00:0A:F7:06:9D:CC",
                      "NIC.Slot.2-2-1" => "00:0A:F7:06:9D:C2",
                      "NIC.Slot.2-2-2" => "00:0A:F7:06:9D:C6",
                      "NIC.Slot.2-2-3" => "00:0A:F7:06:9D:CA",
                      "NIC.Slot.2-2-4" => "00:0A:F7:06:9D:CE"
      }
    end

    it "should find permanent macs" do
      ASM::WsMan.stubs(:invoke).returns(@nic_view_response)
      macs = ASM::WsMan.get_permanent_mac_addresses(nil, nil)
      macs.should == {"NIC.Slot.2-1-1" => "00:0A:F7:06:9D:C0",
                      "NIC.Slot.2-1-2" => "00:0A:F7:06:9D:C4",
                      "NIC.Slot.2-1-3" => "00:0A:F7:06:9D:C8",
                      "NIC.Slot.2-1-4" => "00:0A:F7:06:9D:CC",
                      "NIC.Slot.2-2-1" => "00:0A:F7:06:9D:C2",
                      "NIC.Slot.2-2-2" => "00:0A:F7:06:9D:C6",
                      "NIC.Slot.2-2-3" => "00:0A:F7:06:9D:CA",
                      "NIC.Slot.2-2-4" => "00:0A:F7:06:9D:CE"
      }
    end
  end

  describe "when parsing nicview with enabled 5720 and dual-port slot nic" do
    before do
      # NOTE: this data is from a rack with a dual-port slot nic and a quad-port
      # integrated nic.
      file_name = File.join(File.dirname(__FILE__), "..", "..",
                            "fixtures", "wsman", "nic_view_57800.xml")
      @nic_view_response = File.read(file_name)
    end

    it "should ignore Broadcom 5720 NICs" do
      # we don't have NicView output, so just make the 57810 look like a 5720
      @nic_view_response.gsub!(/(ProductName[>]Broadcom.*)BCM57800/, '\1BCM5720')
      ASM::WsMan.stubs(:invoke).returns(@nic_view_response)
      macs = ASM::WsMan.get_mac_addresses(nil, nil)
      macs.should == {"NIC.Slot.2-1-1" => "00:0A:F7:06:9E:20",
                      "NIC.Slot.2-1-2" => "00:0A:F7:06:9E:24",
                      "NIC.Slot.2-1-3" => "00:0A:F7:06:9E:28",
                      "NIC.Slot.2-1-4" => "00:0A:F7:06:9E:2C",
                      "NIC.Slot.2-2-1" => "00:0A:F7:06:9E:22",
                      "NIC.Slot.2-2-2" => "00:0A:F7:06:9E:26",
                      "NIC.Slot.2-2-3" => "00:0A:F7:06:9E:2A",
                      "NIC.Slot.2-2-4" => "00:0A:F7:06:9E:2E"}
    end
  end

  describe "#deployment_invoke" do
    it "should invoke invoke and parse the command" do
      expected = {:return_value => "0", :foo => "foo"}
      ASM::WsMan.expects(:invoke).with(endpoint, "RspecCommand", ASM::WsMan::DEPLOYMENT_SERVICE_SCHEMA, :logger => logger).returns("<rspec />")
      ASM::WsMan.expects(:parse).with("<rspec />").returns(expected)
      expect(ASM::WsMan.deployment_invoke(endpoint, "RspecCommand", :logger => logger)).to eq(expected)
    end

    it "should fail if the ReturnValue does not match" do
      expected = {:return_value => "2", :message => "Stuff broke"}
      ASM::WsMan.expects(:invoke).with(endpoint, "RspecCommand", ASM::WsMan::DEPLOYMENT_SERVICE_SCHEMA, :logger => logger).returns("<rspec />")
      ASM::WsMan.expects(:parse).with("<rspec />").returns(expected)
      expect do
        ASM::WsMan.deployment_invoke(endpoint, "RspecCommand", :return_value => "0", :logger => logger)
      end.to raise_error("RspecCommand failed: Stuff broke [return_value: 2]")
    end
  end

  describe "#detach_iso_image" do
    it "should invoke DetachISOImage" do
      ASM::WsMan.expects(:deployment_invoke).with(endpoint, "DetachISOImage", :return_value => "0", :logger => logger)
      ASM::WsMan.detach_iso_image(endpoint, :logger => logger)
    end
  end

  describe "#disconnect_network_iso_image" do
    it "should invoke DisconnectNetworkISOImage" do
      ASM::WsMan.expects(:deployment_invoke).with(endpoint, "DisconnectNetworkISOImage", :return_value => "0", :logger => logger)
      ASM::WsMan.disconnect_network_iso_image(endpoint, :logger => logger)
    end
  end

  describe "#get_attach_status" do
    it "should invoke GetAttachStatus" do
      ASM::WsMan.expects(:deployment_invoke).with(endpoint, "GetAttachStatus", :logger => logger)
      ASM::WsMan.get_attach_status(endpoint, :logger => logger)
    end
  end

  describe "#get_deployment_job" do
    it "should get the job id" do
      job_id = "RspecJob:1"
      url = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_OSDConcreteJob?InstanceID=%s" % job_id
      ASM::WsMan.expects(:invoke).with(endpoint, "get", url, :logger => logger).returns("<rspec>")
      ASM::WsMan.expects(:parse).with("<rspec>").returns(:job_status => "Success")
      expect(ASM::WsMan.get_deployment_job(endpoint, job_id, :logger => logger)).to eq(:job_status => "Success")
    end
  end

  describe "#run_deployment_job" do
    let(:options) do
      {:ip_address => "rspec-ip",
       :image_name => "rspec-microkernel.iso",
       :share_name => "/var/rspec",
       :share_type => :cifs,
       :timeout => 60,
       :logger => logger}
    end

    before(:each) do
      ASM::WsMan.expects(:poll_for_lc_ready).with(endpoint, :logger => logger)
      ASM::WsMan.expects(:osd_deployment_invoke_iso)
        .with(endpoint, "BootToNetworkISO", options)
        .returns(:job => "rspec-job", :job_status => "Started")
    end

    it "should poll for LC ready, invoke command and poll job" do
      ASM::WsMan.expects(:poll_deployment_job).with(endpoint, "rspec-job", options)
        .returns(:job_status => "Success")
      ASM::WsMan.run_deployment_job(endpoint, "BootToNetworkISO", options)
    end

    it "should fail when job fails" do
      ASM::WsMan.expects(:poll_deployment_job).with(endpoint, "rspec-job", options)
        .returns(:job => "rspec-job", :job_status => "Failed")

      expect do
        ASM::WsMan.run_deployment_job(endpoint, "BootToNetworkISO", options)
      end.to raise_error(ASM::WsMan::ResponseError, "BootToNetworkISO job rspec-job failed: Failed [job: rspec-job]")
    end
  end

  describe "#connect_network_iso_image" do
    it "should call run_deployment_job with default timeout of 90 seconds" do
      ASM::WsMan.expects(:run_deployment_job).with(endpoint, "ConnectNetworkISOImage", :timeout => 90)
      ASM::WsMan.connect_network_iso_image(endpoint, {})
    end
  end

  describe "#boot to_network_iso_image" do
    it "should call run_deployment_job with default timeout of 15 minutes" do
      ASM::WsMan.expects(:run_deployment_job).with(endpoint, "BootToNetworkISO", :timeout => 15 * 60)
      ASM::WsMan.boot_to_network_iso_image(endpoint, {})
    end
  end
end
