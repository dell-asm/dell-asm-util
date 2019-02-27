# frozen_string_literal: true

require "spec_helper"
require "asm/firmware"

describe ASM::Firmware do
  let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
  let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
  let(:wsman) { mock("wsman") }
  let(:cred) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
  let(:firmware) { mock("firmware") }

  let(:firmware_obj) { ASM::Firmware.new(endpoint, :logger => logger) }

  let(:config) do
    {"asm::server_update" =>
         {"rackserver-5xclw12" =>
              {"asm_hostname" => "172.25.5.100",
               "path" => "/var/nfs/firmware/ff808081578bd88601578d525d4e004e/ASMCatalog.xml",
               "server_firmware" => "Firmware_path"}}}
  end

  let(:resource_hash) do
    [{"instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
      "uri_path" => "rspec-nfs-path"},
     {"instance_id" => "DCIM:INSTALLED#iDRAC.Embedded.1-1#IDRACinfo",
      "component_id" => "25227",
      "uri_path" => "rspec-nfs-path"}]
  end

  let(:resource_hash2) do
    [{"instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
      "uri_path" => "rspec-nfs-path"},
     {"instance_id" => "DCIM:INSTALLED#701__NIC.Embedded.1-1-1",
      "uri_path" => "rspec-nfs-path"}]
  end

  let(:device_config) do
    {"cert_name" => "rackserver-5xclw12",
     "host" => "rspec-host",
     "port" => nil,
     "path" => "/asm/bin/idrac-discovery.rb",
     "scheme" => "script",
     "arguments" => {"credential_id" => "ff80808157bfd05a0157bfd13392000d"},
     "user" => "rspec-user",
     "enc_password" => nil,
     "password" => "rspec-password"}
  end

  let(:firmware_list) do
    [{"instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
      "uri_path" => "nfs://172.25.5.100/FOLDER03355299M/3/Network_Firmware_35RF5_WN64_7.12.19.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"}]
  end
  let(:firmware_list2) do
    [{"instance_id" => "DCIM:INSTALLED#701__NIC.Embedded.1-1-1",
      "uri_path" => "nfs://172.25.5.100/FOLDER03287319M/3/Network_Firmware_0MT4K_WN64_7.10.64.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"}]
  end
  let(:status) do
    {
      :job_id => "JID_767739984470",
      :status => "new",
      :firmware => {
        "instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
        "uri_path" => "nfs://172.25.5.100/FOLDER03355299M/3/Network_Firmware_35RF5_WN64_7.12.19.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"
      },
      :start_time => Time.now
    }
  end

  let(:status2) do
    {
      :job_id => "JID_767739984470",
      :status => "Scheduled",
      :firmware => {
        "instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
        "uri_path" => "nfs://172.25.5.100/FOLDER03355299M/3/Network_Firmware_35RF5_WN64_7.12.19.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"
      },
      :start_time => Time.now
    }
  end

  let(:status3) do
    {
      :job_id => "JID_123",
      :status => "Completed",
      :firmware => {
        "instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
        "uri_path" => "nfs://172.25.5.100/FOLDER03355299M/3/Network_Firmware_35RF5_WN64_7.12.19.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"
      },
      :start_time => Time.now
    }
  end

  let(:status4) do
    {
      :job_id => "JID_767739984470",
      :status => "new",
      :firmware => {
        "instance_id" => "DCIM:INSTALLED#701__NIC.Slot.2-2-1",
        "uri_path" => "nfs://172.25.5.100/FOLDER03355299M/3/Network_Firmware_35RF5_WN64_7.12.19.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"
      },
      :start_time => Time.now,
      :reboot_required => true,
      :desired => "Scheduled"
    }
  end

  describe "#idrac_fw_install_from_uri" do
    before do
      ASM::WsMan.stubs(:new).with(endpoint, :logger => logger).returns(wsman)
      ASM::Firmware.stubs(:new).with(endpoint, :logger => logger).returns(firmware)
    end

    it "should raise an error when empty resources found" do
      expect { ASM::Firmware.idrac_fw_install_from_uri("123", nil, "rspec-device-config", logger) }.to raise_error("Received empty resources to update the firmware on server")
    end

    it "should upate the firmware" do
      firmware_obj.expects(:clear_job_queue_retry).with(wsman).returns(nil)
      firmware_obj.expects(:update_idrac_firmware).returns(nil).twice
      wsman.expects(:poll_for_lc_ready).twice
      ASM::Firmware.idrac_fw_install_from_uri(config, resource_hash, device_config, logger)
    end

    it "should update the firmware once" do
      firmware.expects(:clear_job_queue_retry).with(wsman).returns(nil)
      firmware.expects(:update_idrac_firmware).returns(nil).once
      wsman.expects(:poll_for_lc_ready)
      ASM::Firmware.idrac_fw_install_from_uri(config, resource_hash2, device_config, logger)
    end
  end

  describe "#clear_job_queue_retry" do
    let(:response) { {:return_value => "0"} }
    let(:response2) { {:return_value => "1"} }
    let(:logger) { stub(:debug => nil, :warn => nil, :info => nil) }
    let(:endpoint) { {:host => "rspec-host", :user => "rspec-user", :password => "rspec-password"} }
    let(:transport) { double("transport") }

    before(:each) do
      ASM::WsMan.stubs(:new).with(endpoint, :logger => logger).returns(wsman)
    end

    it "should clear the job queue successfully" do
      wsman.expects(:delete_job_queue).with(:job_id => "JID_CLEARALL").returns(response)
      wsman.expects(:poll_for_lc_ready)
      firmware_obj.clear_job_queue_retry(wsman)
    end

    it "should try up to 3 times" do
      mock_transport = mock("mock transport")
      mock_transport.expects(:reset_idrac).twice
      firmware_obj.stubs(:sleep).with(60).returns(nil)
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:client).returns(stub(:endpoint => endpoint)).times(2)
      ASM::Transport::Racadm.expects(:new).with(endpoint, logger).returns(mock_transport).times(2)
      wsman.expects(:delete_job_queue).with(:job_id => "JID_CLEARALL").returns(response2)
      wsman.expects(:delete_job_queue).with(:job_id => "JID_CLEARALL_FORCE").twice.returns(response2, response)
      firmware_obj.clear_job_queue_retry(wsman)
    end

    it "should fail after trying three times" do
      mock_transport = mock("mock transport")
      mock_transport.expects(:reset_idrac).twice
      firmware_obj.stubs(:sleep).with(60).returns(nil)
      wsman.expects(:client).returns(stub(:endpoint => endpoint)).times(2)
      ASM::Transport::Racadm.expects(:new).with(endpoint, logger).returns(mock_transport).times(2)
      wsman.expects(:delete_job_queue).with(:job_id => "JID_CLEARALL").returns(response2)
      wsman.expects(:delete_job_queue).with(:job_id => "JID_CLEARALL_FORCE").twice.returns(response2).times(2)
      expect do
        firmware_obj.clear_job_queue_retry(wsman)
      end.to raise_error("Unable to find the LC status after clearing job queue")
    end
  end

  describe "#update_idrac_firmware" do
    it "should update the firmware" do
      firmware_obj.stubs(:gets_install_uri_job).returns("JID_767739984470")
      firmware_obj.stubs(:block_until_downloaded).returns(status2)
      firmware_obj.stubs(:schedule_reboot_job_queue).returns(nil)
      Time.stubs(:now).returns(status[:start_time])
      firmware_obj.stubs(:sleep)
      wsman.stubs(:get_lc_job).with("JID_767739984470").returns("Completed")
      firmware_obj.update_idrac_firmware(firmware_list, false, wsman)
    end

    it "Internal Timeout while Error while updating the firmware" do
      firmware_obj.stubs(:gets_install_uri_job).returns("JID")
      firmware_obj.stubs(:block_until_downloaded).returns(status)
      Time.stubs(:now).returns(status[:start_time] + ASM::Firmware::MAX_WAIT_SECONDS + 1)
      firmware_obj.stubs(:sleep)
      firmware_obj.stubs(:schedule_reboot_job_queue).returns(nil)
      wsman.stubs(:get_lc_job).with("JID_767739984470").returns("Complete")
      expect do
        firmware_obj.update_idrac_firmware(firmware_list, false, wsman)
      end.to raise_error("Firmware update failed in the lifecycle controller. Please refer to LifeCycle job logs")
    end
  end

  describe "#gets_install_uri_job" do
    let(:success_return) do
      {:job => "123", :return_value => "4096"}
    end
    let(:failed_return) do
      {:job => "123", :return_value => "404", :message => "timedout"}
    end
    it "should pass the uri mount path successfully and return job_id" do
      wsman.stubs(:install_from_uri).returns(success_return)
      expect(firmware_obj.gets_install_uri_job(firmware_list.first, wsman)).to eq("123")
    end

    it "should raise an error when install_from_uri job fails" do
      data = {:name => "xyz", :description => "test file"}.to_json
      data.stubs(:path).returns("/tmp")
      File.stubs(:read).with("/tmp").returns("tmp")
      firmware_obj.stubs(:create_xml_config_file).returns(data)
      wsman.stubs(:install_from_uri).returns(failed_return)
      expect do
        firmware_obj.gets_install_uri_job(firmware_list.first, wsman)
      end.to raise_error("Problem running InstallFromURI: timedout")
    end
  end

  describe "#block_until_downloaded" do
    let(:job_status) { {:job_status => "Scheduled"} }
    let(:job_status2) { {:job_status => "Completed"} }
    let(:job_status3) { {:job_status => "Failed"} }
    it "should update the job status to complete" do
      firmware_obj.stubs(:sleep)
      Time.stubs(:now).returns(50)
      wsman.stubs(:get_lc_job).with("JID_123").returns(job_status2)
      expect(firmware_obj.block_until_downloaded("JID_123", firmware_list.first, wsman)).to eq(status3)
    end

    it "should update lc status on second time" do
      firmware_obj.stubs(:sleep).with(30).returns(nil)
      Time.stubs(:now).returns(50)
      wsman.stubs(:get_lc_job).with("JID_123").times(2).returns(job_status, job_status2)
      expect(firmware_obj.block_until_downloaded("JID_123", firmware_list.first, wsman)).to eq(status3)
    end

    it "update status should failed" do
      firmware_obj.stubs(:sleep)
      wsman.stubs(:get_lc_job).with("JID_123").returns(job_status3)
      expect do
        firmware_obj.block_until_downloaded("JID_123", firmware_list.first, wsman)
      end.to raise_error("Firmware update failed in the lifecycle controller.  Please refer to LifeCycle job logs")
    end

    it "should raise error after two times" do
      firmware_obj.stubs(:sleep).with(30).returns(nil)
      wsman.stubs(:get_lc_job).with("JID_123").times(2).returns(job_status, job_status3)
      expect do
        firmware_obj.block_until_downloaded("JID_123", firmware_list.first, wsman)
      end.to raise_error("Firmware update failed in the lifecycle controller.  Please refer to LifeCycle job logs")
    end
  end
end
