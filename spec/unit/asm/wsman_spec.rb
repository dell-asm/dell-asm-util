require "spec_helper"
require "asm/wsman"

describe ASM::WsMan do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
  let(:wsman) { ASM::WsMan.new(endpoint, :logger => logger) }
  let(:client) { wsman.client }

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

  describe "#detach_iso_image" do
    it "should invoke DetachISOImage" do
      client.expects(:invoke).with("DetachISOImage", ASM::WsMan::DEPLOYMENT_SERVICE_SCHEMA, :return_value => "0")
      wsman.detach_iso_image
    end
  end

  describe "#disconnect_network_iso_image" do
    it "should invoke DisconnectNetworkISOImage" do
      client.expects(:invoke).with("DisconnectNetworkISOImage", ASM::WsMan::DEPLOYMENT_SERVICE_SCHEMA, :return_value => "0")
      wsman.disconnect_network_iso_image
    end
  end

  describe "#get_attach_status" do
    it "should invoke GetAttachStatus" do
      client.expects(:invoke).with("GetAttachStatus", ASM::WsMan::DEPLOYMENT_SERVICE_SCHEMA)
      wsman.get_attach_status
    end
  end

  describe "#get_deployment_job" do
    it "should get the job id" do
      job_id = "RspecJob:1"
      url = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_OSDConcreteJob"
      client.expects(:get).with(url, job_id).returns(:job_status => "Success")
      expect(wsman.get_deployment_job(job_id)).to eq(:job_status => "Success")
    end
  end

  describe "#run_deployment_job" do
    let(:iso_method) {:boot_to_network_iso_command}
    let(:options) do
      {:ip_address => "rspec-ip",
       :image_name => "rspec-microkernel.iso",
       :share_name => "/var/rspec",
       :share_type => :cifs,
       :timeout => 60,
       :logger => logger}
    end

    before(:each) do
    end

    it "should poll for LC ready, invoke command and poll job" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:poll_deployment_job).with("rspec-job", :timeout => 300)
        .returns(:job_status => "Success")
      wsman.expects(iso_method).with(:arg1 => "foo").returns(:job => "rspec-job", :job_status => "Started")
      wsman.run_deployment_job(:method => :boot_to_network_iso_command, :timeout => 300, :arg1 => "foo")
    end

    it "should fail when job fails" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:poll_deployment_job).with("rspec-job", :timeout => 300)
        .returns(:job => "rspec-job", :job_status => "Failed")
      wsman.expects(iso_method).returns(:job => "rspec-job", :job_status => "Started")
      expect do
        wsman.run_deployment_job(:method => :boot_to_network_iso_command, :timeout => 300)
      end.to raise_error(ASM::WsMan::ResponseError, "boot_to_network_iso_command job rspec-job failed: Failed [job: rspec-job]")
    end
  end

  describe "#connect_network_iso_image" do
    it "should call run_deployment_job with default timeout of 90 seconds" do
      wsman.expects(:run_deployment_job).with(:method => :connect_network_iso_image_command,
                                              :timeout => 90)
      wsman.connect_network_iso_image
    end
  end

  describe "#boot to_network_iso_image" do
    it "should call run_deployment_job with default timeout of 15 minutes" do
      wsman.expects(:run_deployment_job).with(:method => :boot_to_network_iso_command,
                                              :timeout => 15 * 60)
      wsman.boot_to_network_iso_image
    end
  end
end
