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
      client.expects(:invoke).with("DetachISOImage", ASM::WsMan::DEPLOYMENT_SERVICE, :return_value => "0")
      wsman.detach_iso_image
    end
  end

  describe "#disconnect_network_iso_image" do
    it "should invoke DisconnectNetworkISOImage" do
      client.expects(:invoke).with("DisconnectNetworkISOImage", ASM::WsMan::DEPLOYMENT_SERVICE, :return_value => "0")
      wsman.disconnect_network_iso_image
    end
  end

  describe "#disconnect_rfs_iso_image" do
    it "should invoke DisconnectRFSISOImage" do
      client.expects(:invoke).with("DisconnectRFSISOImage", ASM::WsMan::DEPLOYMENT_SERVICE, :return_value => "0")
      wsman.disconnect_rfs_iso_image
    end
  end

  describe "#rfs_iso_image_connection_info" do
    it "should invoke GetRFSISOImageConnectionInfo" do
      client.expects(:invoke).with("GetRFSISOImageConnectionInfo", ASM::WsMan::DEPLOYMENT_SERVICE)
      wsman.rfs_iso_image_connection_info
    end
  end

  describe "#get_attach_status" do
    it "should invoke GetAttachStatus" do
      client.expects(:invoke).with("GetAttachStatus", ASM::WsMan::DEPLOYMENT_SERVICE).returns("rspec-result")
      expect(wsman.get_attach_status).to eq("rspec-result")
    end
  end

  describe "#fc_views" do
    it "should enumerate DCIM_FCView" do
      client.expects(:enumerate).with("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/DCIM/DCIM_FCView").returns("rspec-result")
      expect(wsman.fc_views).to eq("rspec-result")
    end
  end

  describe "#nic_views" do
    it "should enumerate DCIM_NICView" do
      client.expects(:enumerate).with("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/DCIM/DCIM_NICView").returns("rspec-result")
      expect(wsman.nic_views).to eq("rspec-result")
    end
  end

  describe "#bios_enumerations" do
    it "should enumerate DCIM_BIOSEnumeration" do
      client.expects(:enumerate).with("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_BIOSEnumeration").returns("rspec-result")
      expect(wsman.bios_enumerations).to eq("rspec-result")
    end
  end

  describe "#boot_config_settings" do
    it "should enumerate DCIM_BootConfigSetting" do
      url = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootConfigSetting?__cimnamespace=root/dcim"
      client.expects(:enumerate).with(url).returns("rspec-result")
      expect(wsman.boot_config_settings).to eq("rspec-result")
    end
  end

  describe "#boot_source_settings" do
    it "should enumerate DCIM_BootSourceSetting" do
      url = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootSourceSetting?__cimnamespace=root/dcim"
      client.expects(:enumerate).with(url).returns("rspec-result")
      expect(wsman.boot_source_settings).to eq("rspec-result")
    end
  end

  describe "#get_network_iso_image_connection_info" do
    it "should invoke GetNetworkISOConnectionInfo" do
      client.expects(:invoke).with("GetNetworkISOConnectionInfo", ASM::WsMan::DEPLOYMENT_SERVICE).returns("rspec-result")
      expect(wsman.get_network_iso_image_connection_info).to eq("rspec-result")
    end
  end

  describe "#set_attributes" do
    it "should invoke SetAttributes" do
      client.expects(:invoke).with("SetAttributes", ASM::WsMan::BIOS_SERVICE,
                                   :params => {},
                                   :required_params => [:target, :attribute_name, :attribute_value],
                                   :return_value => "0")
      wsman.set_attributes
    end
  end

  describe "#create_targeted_config_job" do
    it "should invoke CreateTargetedConfigJob" do
      client.expects(:invoke).with("ChangeBootSourceState",
                                   "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootConfigSetting",
                                   :params => {},
                                   :required_params => [:enabled_state, :source],
                                   :url_params => :instance_id,
                                   :return_value => "0")
      wsman.change_boot_source_state
    end
  end

  describe "#change_boot_order_by_instance_id" do
    it "should invoke ChangeBootOrderByInstanceID" do
      client.expects(:invoke).with("ChangeBootOrderByInstanceID",
                                   "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootConfigSetting",
                                   :params => {}, :required_params => :source,
                                   :url_params => :instance_id,
                                   :return_value => ["0", "4096"])
      wsman.change_boot_order_by_instance_id
    end
  end

  describe "#import_system_configuration_command" do
    it "should invoke ImportSystemConfiguration" do
      client.expects(:invoke).with("ImportSystemConfiguration", ASM::WsMan::LC_SERVICE,
                                   :params => {},
                                   :required_params => [:ip_address, :share_name, :file_name, :share_type],
                                   :optional_params => [:target, :shutdown_type, :end_host_power_state, :username, :password],
                                   :return_value => "4096")
      wsman.import_system_configuration_command
    end
  end

  describe "#export_system_configuration_command" do
    it "should invoke ExportSystemConfiguration" do
      client.expects(:invoke).with("ExportSystemConfiguration", ASM::WsMan::LC_SERVICE,
                                   :params => {},
                                   :required_params => [:ip_address, :share_name, :file_name, :share_type],
                                   :optional_params => [:username, :password, :workgroup, :target, :export_use, :include_in_export],
                                   :return_value => "4096")
      wsman.export_system_configuration_command
    end
  end

  describe "#export_complete_lc_log" do
    it "should invoke ExportCompleteLCLog" do
      client.expects(:invoke).with("ExportCompleteLCLog", ASM::WsMan::LC_SERVICE,
                                   :params => {},
                                   :required_params => [:ip_address, :share_name, :file_name, :share_type],
                                   :optional_params => [:username, :password, :workgroup],
                                   :return_value => "4096")
      wsman.export_complete_lc_log
    end
  end

  describe "#get_config_results" do
    it "should invoke GetConfigResults" do
      client.expects(:invoke).with("GetConfigResults", ASM::WsMan::LC_RECORD_LOG_SERVICE,
                                   :params => {},
                                   :optional_params => [:instance_id, :job_id],
                                   :return_value => "0").returns("rspec-result")
      expect(wsman.get_config_results).to eq("rspec-result")
    end
  end

  describe "#create_reboot_job" do
    it "should invoke CreateRebootJob" do
      client.expects(:invoke).with("CreateRebootJob", ASM::WsMan::SOFTWARE_INSTALLATION_SERVICE,
                                   :params => {},
                                   :optional_params => [:reboot_start_time, :reboot_job_type],
                                   :return_value => "4096").returns("rspec-result")
      expect(wsman.create_reboot_job).to eq("rspec-result")
    end
  end

  describe "#setup_job_queue" do
    it "should invoke SetupJobQueue" do
      client.expects(:invoke).with("SetupJobQueue", ASM::WsMan::JOB_SERVICE,
                                   :params => {},
                                   :optional_params => [:job_array, :start_time_interval, :until_time],
                                   :return_value => "0").returns("rspec-result")
      expect(wsman.setup_job_queue).to eq("rspec-result")
    end
  end

  describe "#delete_job_queue" do
    it "should invoke DeleteJobQueue" do
      client.expects(:invoke).with("DeleteJobQueue", ASM::WsMan::JOB_SERVICE,
                                   :params => {},
                                   :optional_params => [:job_id],
                                   :return_value => "0").returns("rspec-result")
      expect(wsman.delete_job_queue).to eq("rspec-result")
    end
  end

  describe "#remote_services_api_status" do
    it "should invoke DeleteJobQueue" do
      client.expects(:invoke).with("GetRemoteServicesAPIStatus", ASM::WsMan::LC_SERVICE).returns("rspec-result")
      expect(wsman.remote_services_api_status).to eq("rspec-result")
    end
  end

  describe "#boot_to_network_iso_command" do
    it "should invoke BootToNetworkISO" do
      client.expects(:invoke)
            .with("BootToNetworkISO", ASM::WsMan::DEPLOYMENT_SERVICE,
                  :params => {},
                  :required_params => [:ip_address, :share_name, :share_type, :image_name],
                  :optional_params => [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect],
                  :return_value => "4096")
            .returns("rspec-result")
      expect(wsman.boot_to_network_iso_command).to eq("rspec-result")
    end
  end

  describe "#connect_network_iso_image_command" do
    it "should invoke ConnectNetworkISOImage" do
      client.expects(:invoke)
            .with("ConnectNetworkISOImage", ASM::WsMan::DEPLOYMENT_SERVICE,
                  :params => {},
                  :required_params => [:ip_address, :share_name, :share_type, :image_name],
                  :optional_params => [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect],
                  :return_value => "4096")
            .returns("rspec-result")
      expect(wsman.connect_network_iso_image_command).to eq("rspec-result")
    end
  end

  describe "#connect_rfs_iso_image_command" do
    it "should invoke ConnectNetworkISOImage" do
      client.expects(:invoke)
            .with("ConnectRFSISOImage", ASM::WsMan::DEPLOYMENT_SERVICE,
                  :params => {},
                  :required_params => [:ip_address, :share_name, :share_type, :image_name],
                  :optional_params => [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect],
                  :return_value => "4096")
            .returns("rspec-result")
      expect(wsman.connect_rfs_iso_image_command).to eq("rspec-result")
    end
  end

  describe "#detach_iso_image" do
    it "should invoke ConnectNetworkISOImage" do
      client.expects(:invoke).with("DetachISOImage", ASM::WsMan::DEPLOYMENT_SERVICE, :return_value => "0").returns("rspec-result")
      expect(wsman.detach_iso_image).to eq("rspec-result")
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

  describe "#reboot" do
    it "should create reboot job, set up job queue and await completion" do
      opts = {:reboot_job_type => :power_cycle,
              :reboot_start_time => "20170101123100",
              :timeout => 900}
      wsman.expects(:create_reboot_job).with(opts).returns(:reboot_job_id => "rspec-job")
      wsman.expects(:setup_job_queue).with(:job_array => "rspec-job", :start_time_interval => "TIME_NOW")
      wsman.expects(:poll_lc_job).with("rspec-job", :timeout => 15 * 60)
      wsman.expects(:poll_for_lc_ready).with(opts).twice
      wsman.reboot(opts)
    end
  end

  describe "#poll_deployment_job" do
    let(:job) { "rspec-job" }

    it "should return result of ASM::Util.block_and_retry_until_ready" do
      resp = {:job_id => job, :job_status => "Success"}
      ASM::Util.expects(:block_and_retry_until_ready).with(1, ASM::WsMan::RetryException, 60).returns(resp)
      expect(wsman.poll_deployment_job(job, :timeout => 1)).to eq(resp)
    end

    it "should return final job status on success" do
      resp = {:job_id => job, :job_status => "Success"}
      wsman.expects(:get_deployment_job).returns(resp)
      expect(wsman.poll_deployment_job(job, :timeout => 1)).to eq(resp)
    end

    it "should raise ResponseError if final status Failed" do
      resp = {:job_id => job, :job_status => "Failed"}
      wsman.expects(:get_deployment_job).returns(resp)
      message = "Deployment job rspec-job failed: Failed [job_id: rspec-job]"
      expect {wsman.poll_deployment_job(job, :timeout => 1)}.to raise_error(message)
    end

    it "should time out otherwise" do
      resp = {:job_id => job, :job_status => "Running"}
      wsman.expects(:get_deployment_job).returns(resp).at_least_once
      message = "Timed out waiting for job rspec-job to complete. Final status: Running [job_id: rspec-job]"
      expect {wsman.poll_deployment_job(job, :timeout => 0.05)}.to raise_error(message)
    end
  end

  describe "#get_lc_job" do
    it "should get the job id" do
      job_id = "RspecJob:1"
      url = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_LifecycleJob"
      client.expects(:get).with(url, job_id).returns(:job_status => "Success")
      expect(wsman.get_lc_job(job_id)).to eq(:job_status => "Success")
    end
  end

  describe "#poll_lc_job" do
    let(:job) { "rspec-job" }

    it "should return result of ASM::Util.block_and_retry_until_ready" do
      resp = {:job_id => job, :job_status => "Complete"}
      ASM::Util.expects(:block_and_retry_until_ready).with(1, ASM::WsMan::RetryException, 60).returns(resp)
      expect(wsman.poll_lc_job(job, :timeout => 1)).to eq(resp)
    end

    it "should return final job status on success" do
      resp = {:job_id => job, :job_status => "Complete"}
      wsman.expects(:get_lc_job).returns(resp)
      expect(wsman.poll_lc_job(job, :timeout => 1)).to eq(resp)
    end

    it "should raise ResponseError if final status not complete" do
      resp = {:job_id => job, :job_status => "Failed", :percent_complete => "100"}
      wsman.expects(:get_lc_job).returns(resp)
      message = "LC job rspec-job failed: Failed [job_id: rspec-job, percent_complete: 100]"
      expect {wsman.poll_lc_job(job, :timeout => 1)}.to raise_error(message)
    end

    it "should time out otherwise" do
      resp = {:job_id => job, :job_status => "Running"}
      wsman.expects(:get_lc_job).returns(resp).at_least_once
      message = "Timed out waiting for job rspec-job to complete. Final status: Running [job_id: rspec-job]"
      expect {wsman.poll_lc_job(job, :timeout => 0.05)}.to raise_error(message)
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
  end

  describe "#run_bios_config" do
    it "should create bios job and await commpletion" do
      opts = {:scheduled_start_time => "yyyymmddhhmmss", :reboot_job_type => :power_cycle}
      wsman.expects(:poll_for_lc_ready).twice
      wsman.expects(:create_targeted_config_job).with(opts).returns(:job => "rspec-job")
      wsman.expects(:poll_lc_job).with("rspec-job", :timeout => 1800).returns(:job => "rspec-job", :job_status => "Success")
      wsman.run_bios_config_job(opts)
    end
  end

  describe "#set_bios_attributes" do
    it "should set the attributes and run the bios config job" do
      wsman.expects(:set_attributes).with("rspec-attrs")
      wsman.expects(:run_bios_config_job).with("rspec-attrs")
      wsman.set_bios_attributes("rspec-attrs")
    end
  end

  describe "#find_boot_device" do
    it "should find boot device by instance_id" do
      boot_devices = [{:instance_id => "#Foo#"}]
      wsman.expects(:boot_source_settings).returns(boot_devices)
      expect(wsman.find_boot_device("Foo")).to eq(boot_devices.first)
    end

    it "should find boot device by :hdd alias" do
      boot_devices = [{:instance_id => "#HardDisk.List.1-1#"}]
      wsman.expects(:boot_source_settings).returns(boot_devices)
      expect(wsman.find_boot_device(:hdd)).to eq(boot_devices.first)
    end

    it "should not find boot device if it doesn't exist" do
      wsman.expects(:boot_source_settings).returns([])
      expect(wsman.find_boot_device(:hdd)).to be_nil
    end
  end

  describe "#set_boot_order" do
    let(:opts) {{:scheduled_start_time => "yyyymmddhhmmss", :reboot_job_type => :power_cycle}}

    it "should fail if BootMode not found" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:bios_enumerations).returns([])
      expect {wsman.set_boot_order(:virtual_cd, opts)}.to raise_error("BootMode not found")
    end

    it "should set bios boot mode if uefi set" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:bios_enumerations).returns([{:fqdd => "BiosFqdd", :attribute_name => "BootMode", :current_value => "Uefi"}])
      wsman.expects(:set_bios_attributes).with(:target => "BiosFqdd", :attribute_name => "BootMode", :attribute_value => "Bios")
      wsman.expects(:find_boot_device).with(:virtual_cd).returns(:instance_id => "rspec-id", :current_assigned_sequence => 5)
      wsman.expects(:change_boot_order_by_instance_id).with(:instance_id => "IPL", :source => "rspec-id")
      wsman.expects(:change_boot_source_state).with(:instance_id => "IPL", :enabled_state => "1", :source => "rspec-id")
      wsman.expects(:run_bios_config_job).with(opts.merge(:target => "BiosFqdd"))
      wsman.set_boot_order(:virtual_cd, opts)
    end

    it "should fail if boot target cannot be found" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:bios_enumerations).returns([{:fqdd => "BiosFqdd", :attribute_name => "BootMode", :current_value => "Uefi"}])
      wsman.expects(:set_bios_attributes).with(:target => "BiosFqdd", :attribute_name => "BootMode", :attribute_value => "Bios")
      wsman.expects(:find_boot_device).with(:virtual_cd).returns(nil)
      wsman.expects(:boot_source_settings).returns(%w(Hdd VirtualCd Nic).map { |e| {:element_name => e}})
      message = "Could not find virtual_cd boot device in current list: Hdd, VirtualCd, Nic"
      expect {wsman.set_boot_order(:virtual_cd, opts)}.to raise_error(message)
    end

    it "should exit early if boot order already set correctly" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:bios_enumerations).returns([{:fqdd => "BiosFqdd", :attribute_name => "BootMode", :current_value => "Bios"}])
      wsman.expects(:find_boot_device).with(:virtual_cd)
           .returns(:instance_id => "rspec-id",
                    :current_assigned_sequence => "0",
                    :current_enabled_status => "1")
      wsman.expects(:change_boot_order_by_instance_id).never
      wsman.expects(:change_boot_source_state).never
      wsman.expects(:run_bios_config_job).never
      wsman.set_boot_order(:virtual_cd, opts)
    end

    it "should set boot order and run bios config job otherwise" do
      wsman.expects(:poll_for_lc_ready)
      wsman.expects(:bios_enumerations).returns([{:fqdd => "BiosFqdd", :attribute_name => "BootMode", :current_value => "Bios"}])
      wsman.expects(:find_boot_device).with(:virtual_cd).returns(:instance_id => "rspec-id", :current_assigned_sequence => 5)
      wsman.expects(:change_boot_order_by_instance_id).with(:instance_id => "IPL", :source => "rspec-id")
      wsman.expects(:change_boot_source_state).with(:instance_id => "IPL", :enabled_state => "1", :source => "rspec-id")
      wsman.expects(:run_bios_config_job).with(opts.merge(:target => "BiosFqdd"))
      wsman.set_boot_order(:virtual_cd, opts)
    end
  end

  describe "#boot_rfs_iso_image" do
    let(:opts) {{:reboot_start_time => "yyyymmddhhmmss", :reboot_job_type => :power_cycle, :timeout => 600}}

    it "should connect iso, reboot, wait and set boot order" do
      wsman.expects(:connect_rfs_iso_image).with(opts)
      wsman.expects(:reboot).with(opts)
      ASM::Util.expects(:block_and_retry_until_ready).with(600, ASM::WsMan::RetryException, 60)
      wsman.expects(:set_boot_order).with(:virtual_cd)
      wsman.boot_rfs_iso_image(opts)
    end

    it "should connect iso, reboot, set boot order when target device found" do
      wsman.expects(:connect_rfs_iso_image).with(opts)
      wsman.expects(:reboot).with(opts)
      wsman.expects(:find_boot_device).with(:virtual_cd).returns({})
      wsman.expects(:set_boot_order).with(:virtual_cd)
      wsman.boot_rfs_iso_image(opts)
    end

    it "should connect iso, reboot, set boot order and fail if target device not found" do
      opts[:timeout] = 0.05
      wsman.expects(:connect_rfs_iso_image).with(opts)
      wsman.expects(:reboot).with(opts)
      wsman.expects(:find_boot_device).with(:virtual_cd).returns(nil)
      message = "Timed out waiting for virtual CD to become available on rspec-host"
      expect {wsman.boot_rfs_iso_image(opts)}.to raise_error(message)
    end
  end

  describe "#connect_network_iso_image" do
    it "should call run_deployment_job with default timeout of 90 seconds" do
      wsman.expects(:run_deployment_job).with(:method => :connect_network_iso_image_command,
                                              :timeout => 90)
      wsman.connect_network_iso_image
    end
  end

  describe "#connect_rfs_iso_image" do
    it "should call run_deployment_job with default timeout of 90 seconds" do
      wsman.expects(:rfs_iso_image_connection_info).returns(:return_value => "2")
      wsman.expects(:run_deployment_job).with(:method => :connect_rfs_iso_image_command,
                                              :timeout => 90)
      wsman.connect_rfs_iso_image
    end

    it "should disconnect old images first" do
      wsman.expects(:rfs_iso_image_connection_info).returns(:return_value => "0")
      wsman.expects(:disconnect_rfs_iso_image)
      wsman.expects(:run_deployment_job).with(:method => :connect_rfs_iso_image_command,
                                              :timeout => 90)
      wsman.connect_rfs_iso_image
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
