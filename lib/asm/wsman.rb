# coding: utf-8
require "pathname"
require "asm/network_configuration/nic_info"
require "asm/util"
require "asm/wsman/client"
require "asm/wsman/parser"
require "asm/wsman/response_error"
require "rexml/document"

module ASM
  class WsMan
    # rubocop:disable Metrics/LineLength
    BIOS_SERVICE = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_BIOSService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_BIOSService,SystemName=DCIM:ComputerSystem,Name=DCIM:BIOSService".freeze
    DEPLOYMENT_SERVICE = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_OSDeploymentService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_OSDeploymentService,SystemName=DCIM:ComputerSystem,Name=DCIM:OSDeploymentService".freeze
    JOB_SERVICE = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_JobService?CreationClassName=DCIM_JobService,Name=JobService,SystemName=Idrac,SystemCreationClassName=DCIM_ComputerSystem".freeze
    LC_SERVICE = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_LCService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_LCService,SystemName=DCIM:ComputerSystem,Name=DCIM:LCService".freeze
    LC_RECORD_LOG_SERVICE = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_LCRecordLog?__cimnamespace=root/dcim".freeze
    POWER_SERVICE = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_ComputerSystem?CreationClassName=DCIM_ComputerSystem,Name=srv:system".freeze
    SOFTWARE_INSTALLATION_SERVICE = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_SoftwareInstallationService?CreationClassName=DCIM_SoftwareInstallationService,SystemCreationClassName=DCIM_ComputerSystem,SystemName=IDRAC:ID,Name=SoftwareUpdate".freeze
    # rubocop:enable Metrics/LineLength

    attr_reader :client

    def initialize(endpoint, options={})
      @client = Client.new(endpoint, options)
    end

    def logger
      client.logger
    end

    def host
      client.host
    end

    # @deprecated use {Client#invoke} instead.
    def self.invoke(endpoint, method, schema, options={})
      WsMan.new(endpoint, options).client.exec(method, schema, options)
    end

    # Retrieve FC NIC information
    #
    # @return [Array<Hash>]
    def fc_views
      client.enumerate("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/DCIM/DCIM_FCView")
    end

    # Retrieve ethernet NIC information
    #
    # @return [Array<Hash>]
    #
    # @example return
    #   [{:auto_negotiation=>"3",
    #     :bus_number=>"129",
    #     :controller_bios_version=>nil,
    #     :current_mac_address=>"00:8C:FA:F0:6F:5A",
    #     :data_bus_width=>"0002",
    #     :device_description=>"Embedded NIC 1 Port 1 Partition 1",
    #     :device_number=>"0",
    #     :efi_version=>"4.6.14",
    #     :fcoe_offload_mode=>"3",
    #     :fcoe_wwnn=>"00:8c:fa:f0:6f:5b",
    #     :fqdd=>"NIC.Embedded.1-1-1",
    #     :family_version=>"16.5.0",
    #     :function_number=>"0",
    #     :instance_id=>"NIC.Embedded.1-1-1",
    #     :last_system_inventory_time=>"20160103092723.000000+000",
    #     :last_update_time=>"20151121053023.000000+000",
    #     :link_duplex=>"1",
    #     :link_speed=>"5",
    #     :max_bandwidth=>"0",
    #     :media_type=>"SFP_PLUS",
    #     :min_bandwidth=>"0",
    #     :nic_mode=>"3",
    #     :pci_device_id=>"10fb",
    #     :pci_sub_device_id=>"06ee",
    #     :pci_sub_vendor_id=>"1028",
    #     :pci_vendor_id=>"8086",
    #     :permanent_fcoe_mac_address=>"",
    #     :permanent_mac_address=>"00:8C:FA:F0:6F:5A",
    #     :permanent_iscsi_mac_address=>"",
    #     :product_name=>"Intel(R) Ethernet 10G X520 LOM - 00:8C:FA:F0:6F:5A",
    #     :protocol=>"NIC",
    #     :receive_flow_control=>"2",
    #     :slot_length=>"0002",
    #     :slot_type=>"0002",
    #     :transmit_flow_control=>"2",
    #     :vendor_name=>"Intel Corp",
    #     :virt_wwn=>"20:00:00:8C:FA:F0:6F:5B",
    #     :virt_wwpn=>"20:01:00:8C:FA:F0:6F:5B",
    #     :wwn=>nil,
    #     :wwpn=>"20:00:00:8C:FA:F0:6F:5B",
    #     :iscsi_offload_mode=>"3"}, # ...
    #    ]
    def nic_views
      client.enumerate("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/DCIM/DCIM_NICView")
    end

    # Retrieve list of BIOS settings
    #
    # @return [Array<Hash>]
    #
    # @example return
    #     [{:attribute_display_name=>"System Memory Testing",
    #       :attribute_name=>"MemTest",
    #       :current_value=>"Disabled",
    #       :dependency=>nil,
    #       :display_order=>"310",
    #       :fqdd=>"BIOS.Setup.1-1",
    #       :group_display_name=>"Memory Settings",
    #       :group_id=>"MemSettings",
    #       :instance_id=>"BIOS.Setup.1-1:MemTest",
    #       :is_read_only=>"false",
    #       :pending_value=>nil,
    #       :possible_values=>"Disabled",
    #       :possible_values_description=>"Disabled"}, # ...
    #     ]
    def bios_enumerations
      client.enumerate("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_BIOSEnumeration")
    end

    # Retrieve boot configuration settings
    #
    # In each boot configuration setting, enumeration values are:
    #
    # - :is_current "1" if the setting is the current boot configuration, "2" if it is not
    # - :is_default Always "0". Default boot configurations are not supported.
    # - :is_next
    #   - "1" if the setting is the next boot configuration the system will use for booting
    #   - "2" if it is not the next boot configuration the system will use for booting
    #   - "3" if it is the next boot configuration the system will use for booting for single use, one time boot only
    #
    # @return [Array<Hash>]
    #
    # @example return
    #     [{:element_name=>"BootSeq",
    #       :instance_id=>"IPL",
    #       :is_current=>"1",
    #       :is_default=>"0",
    #       :is_next=>"1"}, # ...
    #     ]
    def boot_config_settings
      client.enumerate("http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootConfigSetting?__cimnamespace=root/dcim")
    end

    # Retrieve boot source settings
    #
    # In each boot configuration setting, enumeration values are:
    #
    # - :current_enabled_sequence "0" for disabled, "1" for enabled
    # - :pending_enabled_sequence "0" for disabled, "1" for enabled
    # - :fall_through_supported "0" for unknown, "1" for supported, and "2" for not supported
    #
    # @return [Array<Hash>]
    #
    # @example return
    #     [{:bios_boot_string=>"Embedded NIC 2 Port 1 Partition 1: IBA XE Slot 8101 v2334 BootSeq",
    #       :boot_source_type=>"IPL",
    #       :boot_string=>"Embedded NIC 2 Port 1 Partition 1: IBA XE Slot 8101 v2334 BootSeq",
    #       :current_assigned_sequence=>"0",
    #       :current_enabled_status=>"1",
    #       :element_name=>"Embedded NIC 2 Port 1 Partition 1: IBA XE Slot 8101 v2334 BootSeq",
    #       :fail_through_supported=>"1",
    #       :instance_id=>"IPL:BIOS.Setup.1-1#BootSeq#NIC.Embedded.2-1-1#325788652d3efc5da1073089dbd3ba90",
    #       :pending_assigned_sequence=>"0",
    #       :pending_enabled_status=>"1"}, # ...
    #     ]
    def boot_source_settings
      client.enumerate("http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootSourceSetting?__cimnamespace=root/dcim")
    end

    # Get power state information
    #
    # @return [String] The value will be "2" if the server is on and "13" if it is off.
    def power_state
      ret = client.enumerate("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_CSAssociatedPowerManagementService")
      raise(Error, "No power management enumerations found") if ret.empty?
      ret.first[:power_state]
    end

    def self.reboot(endpoint, logger=nil)
      # Create the reboot job
      logger.debug("Rebooting server #{endpoint[:host]}") if logger
      instanceid = invoke(endpoint,
                          "CreateRebootJob",
                          SOFTWARE_INSTALLATION_SERVICE,
                          :selector => '//wsman:Selector Name="InstanceID"',
                          :props => {"RebootJobType" => "1"},
                          :logger => logger)

      # Execute job
      jobmessage = invoke(endpoint,
                          "SetupJobQueue",
                          JOB_SERVICE,
                          :selector => "//n1:Message",
                          :props => {
                            "JobArray" => instanceid,
                            "StartTimeInterval" => "TIME_NOW"
                          },
                          :logger => logger)
      logger.debug "Job Message #{jobmessage}" if logger
      true
    end

    # @deprecated Use {#power_off} instead.
    def self.poweroff(endpoint, logger=nil)
      ASM::WsMan.new(endpoint, :logger => logger).power_off
    end

    # @deprecated Use {#power_on} instead.
    def self.poweron(endpoint, logger=nil)
      ASM::WsMan.new(endpoint, :logger => logger).power_on
    end

    def self.get_power_state(endpoint, logger=nil)
      WsMan.new(endpoint, :logger => logger).power_state
    end

    def self.get_wwpns(endpoint, logger=nil)
      response = invoke(endpoint, "enumerate",
                        "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/DCIM/DCIM_FCView",
                        :logger => logger)
      response.split(/\n/).collect do |ele|
        $1 if ele =~ %r{<n1:VirtualWWPN>(\S+)</n1:VirtualWWPN>}
      end.compact
    end

    def self.nic_status(fqdd, bios_info)
      fqdd_display = bios_display_name(fqdd)
      nic_enabled = "Enabled"
      bios_info.each do |bios_ele|
        if bios_ele["AttributeDisplayName"] == fqdd_display
          nic_enabled = bios_ele["CurrentValue"]
          break
        end
      end
      nic_enabled
    end

    def self.bios_display_name(fqdd)
      display_name = fqdd
      fqdd_info = fqdd.scan(/NIC.(\S+)\.(\S+)-(\d+)-(\d+)/).flatten
      case fqdd_info[0]
      when "Mezzanine"
        display_name = "Mezzanine Slot #{fqdd_info[1]}"
      when "Integrated"
        display_name = "Integrated Network Card 1"
      when "Slot"
        display_name = "Slot #{fqdd_info[1]}"
      end
      display_name
    end

    # Return all 10Gb, enabled current server MAC Address along with the interface
    # location in a hash format.
    #
    # @deprecated Use {ASM::NetworkConfiguration::NicInfo} instead to find NIC capabilities
    def self.get_mac_addresses(endpoint, logger=nil)
      nics = NetworkConfiguration::NicInfo.fetch(endpoint, logger)
      ret = {}
      nics.reject(&:disabled?).each do |nic|
        nic.ports.each do |port|
          next unless port.link_speed == "10 Gbps"
          port.partitions.each do |partition|
            ret[partition.fqdd] = partition.mac_address
          end
        end
      end
      logger.debug("********* MAC Address List is #{ret.inspect} **************") if logger
      ret
    end

    # Return all 10Gb, enabled permanent server MAC Address along with the interface
    # location in a hash format.
    #
    # @deprecated Use {ASM::NetworkConfiguration::NicInfo} instead to find NIC capabilities
    def self.get_permanent_mac_addresses(endpoint, logger=nil)
      nics = NetworkConfiguration::NicInfo.fetch(endpoint, logger)
      ret = {}
      nics.reject(&:disabled?).each do |nic|
        nic.ports.each do |port|
          next unless port.link_speed == "10 Gbps"
          port.partitions.each do |partition|
            ret[partition.fqdd] = partition["PermanentMACAddress"]
          end
        end
      end
      logger.debug("********* MAC Address List is #{ret.inspect} **************") if logger
      ret
    end

    # Gets Nic View data
    def self.get_nic_view(endpoint, logger=nil, tries=0)
      resp = invoke(endpoint, "enumerate",
                    "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_NICView",
                    :logger => logger)
      nic_views = resp.split("<n1:DCIM_NICView>")
      nic_views.shift
      ret = nic_views.collect do |nic_view|
        nic_view.split("\n").inject({}) do |acc, line|
          if line =~ %r{<n1:(\S+).*>(.*)</n1:\S+>}
            acc[$1] = $2
          elsif line =~ %r{<n1:(\S+).*/>}
            acc[$1] = nil
          end
          acc
        end
      end

      # Apparently we sometimes see a spurious empty return value...
      if ret.empty? && tries == 0
        ret = get_nic_view(endpoint, logger, tries + 1)
      end
      ret
    end

    # Gets Nic View data
    def self.get_bios_enumeration(endpoint, logger=nil)
      resp = invoke(endpoint, "enumerate",
                    "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_BIOSEnumeration",
                    :logger => logger)
      bios_enumeration = resp.split("<n1:DCIM_BIOSEnumeration>")
      bios_enumeration.shift
      bios_enumeration.collect do |bios_view|
        bios_view.split("\n").inject({}) do |ret, line|
          if line =~ %r{<n1:(\S+).*>(.*)</n1:\S+>}
            ret[$1] = $2
          elsif line =~ %r{<n1:(\S+).*/>}
            ret[$1] = nil
          end
          ret
        end
      end
    end

    # Gets Nic View data for a specified fqdd
    def self.get_fcoe_wwpn(endpoint, logger=nil)
      fcoe_info = {}
      resp = invoke(endpoint, "enumerate",
                    "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_NICView",
                    :logger => logger)
      nic_views = resp.split("<n1:DCIM_NICView>")
      nic_views.shift
      nic_views.each do |nic_view|
        nic_name = nil
        nic_view.split("\n").each do |line|
          if line =~ %r{<n1:FQDD>(\S+)</n1:FQDD>}
            nic_name = $1
            fcoe_info[nic_name] = {}
          end
        end
        nic_view.split("\n").each do |line|
          if line =~ %r{<n1:FCoEWWNN>(\S+)</n1:FCoEWWNN>}
            fcoe_wwnn = $1
            fcoe_info[nic_name]["fcoe_wwnn"] = fcoe_wwnn
          end

          if line =~ %r{<n1:PermanentFCOEMACAddress>(\S+)</n1:PermanentFCOEMACAddress>}
            fcoe_permanent_fcoe_macaddress = $1
            fcoe_info[nic_name]["fcoe_permanent_fcoe_macaddress"] = fcoe_permanent_fcoe_macaddress
          end

          if line =~ %r{<n1:FCoEOffloadMode>(\S+)</n1:FCoEOffloadMode>}
            fcoe_offload_mode = $1
            fcoe_info[nic_name]["fcoe_offload_mode"] = fcoe_offload_mode
          end

          if line =~ %r{<n1:VirtWWN>(\S+)</n1:VirtWWN>}
            virt_wwn = $1
            fcoe_info[nic_name]["virt_wwn"] = virt_wwn
          end

          if line =~ %r{<n1:VirtWWPN>(\S+)</n1:VirtWWPN>}
            virt_wwpn = $1
            fcoe_info[nic_name]["virt_wwpn"] = virt_wwpn
          end

          if line =~ %r{<n1:WWN>(\S+)</n1:WWN>}
            wwn = $1
            fcoe_info[nic_name]["wwn"] = wwn
          end

          if line =~ %r{<n1:WWPN>(\S+)</n1:WWPN>}
            wwpn = $1
            fcoe_info[nic_name]["wwpn"] = wwpn
          end
        end
      end

      # Remove the Embedded NICs from the list
      fcoe_info.keys.each do |nic_name|
        fcoe_info.delete(nic_name) if nic_name.include?("Embedded")
      end

      logger.debug("FCoE info: #{fcoe_info.inspect} **************") if logger
      fcoe_info
    end

    # Gets LC status
    def self.lcstatus(endpoint, logger=nil)
      invoke(endpoint, "GetRemoteServicesAPIStatus", LC_SERVICE, :selector => "//n1:LCStatus", :logger => logger)
    end

    # Create a job to reboot the server
    #
    # @param options [Hash]
    # @option options [String] :reboot_start_time Scheduled start time of Reboot. Format: yyyymmddhhmmss. A special
    #                           value of "TIME_NOW" schedules the job(s) immediately. Required.
    # @option params [String] :reboot_job_type "1" or :power_cycle, "2" or :graceful, or "3" or :graceful_with_forced_shutdown. Required.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def create_reboot_job(params={})
      client.invoke("CreateRebootJob", SOFTWARE_INSTALLATION_SERVICE,
                    :params => params,
                    :optional_params => [:reboot_start_time, :reboot_job_type],
                    :return_value => "4096")
    end

    # Set up a job queue with jobs to execute
    #
    # This method is used for creating a job queue that shall contain one or more
    # LC jobs with a specified order of execution within the queue.
    #
    # @param options [Hash]
    # @option options [String] :job_array Array containing the value of the InstanceID property of the instances of
    #                          DCIM_LifeCycleJob that represent the set of jobs to add to the job queue. This is an
    #                          ordered array that represents the sequence in which the jobs are run.
    # @option params [String] :start_time_interval Start time for the job execution in format: yyyymmddhhmmss. The
    #                         string "TIME_NOW" means immediate.
    # @option params [String] :until_time End time for the job execution in format: yyyymmddhhmmss. If this
    #                         parameter is not NULL, then StartTimeInterval parameter shall also be specified.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def setup_job_queue(params={})
      client.invoke("SetupJobQueue", JOB_SERVICE,
                    :params => params,
                    :optional_params => [:job_array, :start_time_interval, :until_time],
                    :return_value => "0")
    end

    # Delete one or all jobs from the job queue
    #
    # @param options [Hash]
    # @option options [String] :job_id The InstanceID property of the instances of DCIM_LifeCycleJob that represent
    #                          the job to be deleted. The value "JID_CLEARALL for the JobID will clear all the jobs.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def delete_job_queue(params={})
      client.invoke("DeleteJobQueue", JOB_SERVICE,
                    :params => params,
                    :optional_params => [:job_id],
                    :return_value => "0")
    end

    # Get the lifecycle controller (LC) status
    #
    # An lcstatus of "0" indicates that the LC is ready to accept new jobs.
    #
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    #
    # @example ready response
    #   {:lcstatus=>"0", :message=>"Lifecycle Controller Remote Services is ready.",
    #    :message_id=>"LC061", :rtstatus=>"0", :return_value=>"0", :server_status=>"2", :status=>"0"}
    #
    # @example busy response
    #   {:lcstatus=>"5", :message=>"Lifecycle Controller Remote Services is not ready.",
    #    :message_id=>"LC060", :rtstatus=>"1", :return_value=>"0", :server_status=>"1", :status=>"1"}
    #
    def remote_services_api_status
      client.invoke("GetRemoteServicesAPIStatus", LC_SERVICE)
    end

    # Reboot server to a network ISO
    #
    # @note {detach_iso_image} should be called once the ISO is no longer needed.
    # @param options [Hash]
    # @option options [String] :ip_address CIFS or NFS share IPv4 address. For example, 192.168.10.100. Required.
    # @option options [String] :share_name NFS or CIFS network share point. For example, "/home/guest" or "guest_smb.". Required.
    # @option options [String] :image_name ISO image name. Required.
    # @option options [String|Fixnum] :share_type share type. 0 or :nfs for NFS and 2 or :cifs for CIFS. Required.
    # @option options [String] :workgroup workgroup name, if applicable
    # @option options [String] :user_name user name, if applicable.
    # @option options [String] :password password, if applicable
    # @option options [String] :hash_type type of hash algorithm used to compute checksum: 1 or :md5 for MD5 and 2 or :sha1 for SHA1
    # @option options [String] :hash_value checksum value in string format computed using HashType algorithm
    # @option options [String] :auto_connect auto-connect to ISO image up on iDRAC reset
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def boot_to_network_iso_command(params={})
      client.invoke("BootToNetworkISO", DEPLOYMENT_SERVICE,
                    :params => params,
                    :required_params => [:ip_address, :share_name, :share_type, :image_name],
                    :optional_params => [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect],
                    :return_value => "4096")
    end

    # Connect a network ISO as a virtual CD-ROM
    #
    # The normal server boot order will be ignored after this call has been made.
    # The server will only boot into the network ISO until {disconnect_network_iso_image}
    # is called. The LC controller will be locked while the server is in this
    # state and no other LC jobs can be run.
    #
    # @param (see #boot_to_network_iso_command)
    # @raise [ResponseError] if the command fails
    def connect_network_iso_image_command(params={})
      client.invoke("ConnectNetworkISOImage", DEPLOYMENT_SERVICE,
                    :params => params,
                    :required_params => [:ip_address, :share_name, :share_type, :image_name],
                    :optional_params => [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect],
                    :return_value => "4096")
    end

    # Connect a network ISO from a remote file system
    #
    # The ISO will become available as a virtual CD boot option. In order to
    # boot off the ISO the normal server boot order must be separately configured.
    # Unlike {connect_network_iso_image}, this method will not lock the LC controller
    # and other LC jobs can be run as usual.
    #
    # @note {#disconnect_rfs_iso_image} should be called as soon as the ISO is not needed.
    # @param (see #boot_to_network_iso_command)
    # @return [Hash]
    # @raise [ASM::ResponseError] if the command fails
    #
    # @example response
    #     {:job=>"DCIM_OSDConcreteJob:1", :return_value=>"4096"}
    def connect_rfs_iso_image_command(params={})
      client.invoke("ConnectRFSISOImage", DEPLOYMENT_SERVICE,
                    :params => params,
                    :required_params => [:ip_address, :share_name, :share_type, :image_name],
                    :optional_params => [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect],
                    :return_value => "4096")
    end

    # Detach an ISO that was mounted with {#boot_to_network_iso_command}
    #
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    def detach_iso_image
      client.invoke("DetachISOImage", DEPLOYMENT_SERVICE, :return_value => "0")
    end

    # @deprecated Use {detach_iso_image} instead.
    def self.detach_network_iso(endpoint, logger=nil)
      WsMan.new(endpoint, :logger => logger).detach_iso_image
    end

    # Disconnect an ISO that was mounted with {#connect_network_iso_image_command}
    #
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    def disconnect_network_iso_image
      client.invoke("DisconnectNetworkISOImage", DEPLOYMENT_SERVICE, :return_value => "0")
    end

    # Disconnect an ISO that was mounted with {#connect_rfs_iso_image_command}
    #
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    def disconnect_rfs_iso_image
      client.invoke("DisconnectRFSISOImage", DEPLOYMENT_SERVICE, :return_value => "0")
    end

    # Gets the RFS ISO image connection status
    #
    # @see {#connect_rfs_iso_image_command}
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    #
    # @example connected response
    #     {:file_path=>"172.25.3.100:/var/nfs/ipxe.iso", :return_value=>"0"}
    #
    # @example disconnected response
    #     {:message=>"Unable to connect to ISO using Remote File Share (RFS).",
    #      :message_id=>"OSD60",
    #      :return_value=>"2"}
    def rfs_iso_image_connection_info
      client.invoke("GetRFSISOImageConnectionInfo", DEPLOYMENT_SERVICE)
    end

    # Get current drivers and ISO connection status
    #
    # The drivers and iso attach status will be reported as "0" for not attached
    # and "1" for "attached". The overall return_value will be non-zero if nothing
    # is currently attached.
    #
    # The ISO will show as attached if either {boot_to_network_iso_command} or
    # {connect_network_iso_image_command} have been executed.
    #
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    #
    # @example response
    #   {:drivers_attach_status=>"0", :iso_attach_status=>"1", :return_value=>"0"}
    def get_attach_status # rubocop:disable Style/AccessorMethodName
      client.invoke("GetAttachStatus", DEPLOYMENT_SERVICE)
    end

    # Get ISO image connection info
    #
    # The ISO attach status will be "0" for not attached and "1" for attached.
    #
    # The ISO will show as attached only if the {connect_network_iso_image_command}
    # has been executed.
    #
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    #
    # @example response
    #   {:host_attached_status=>"1", :host_booted_from_iso=>"1",
    #    :ipaddr=>"172.25.3.100", :iso_connection_status=>"1",
    #    :image_name=>"ipxe.iso", :return_value=>"0", :share_name=>"/var/nfs"}
    def get_network_iso_image_connection_info # rubocop:disable Style/AccessorMethodName
      client.invoke("GetNetworkISOConnectionInfo", DEPLOYMENT_SERVICE)
    end

    # Set BIOS attribute values
    #
    # Queues up BIOS attribute value settings to apply. {#create_targeted_config_job}
    # must be called to reboot the server and apply the settings.
    #
    # @note {#set_bios_attributes} can be used to apply settings and wait for completion.
    #
    # @param params [Hash]
    # @option params [String] :target The BIOS FQDD. Usually "BIOS.Setup.1-1".
    # @option params [String] :attribute_name The attribute name(s) to be modified.
    # @option params [String] :attribute_value The attribute value(s) to set them to.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def set_attributes(params={}) # rubocop:disable Style/AccessorMethodName
      client.invoke("SetAttributes", BIOS_SERVICE,
                    :params => params,
                    :required_params => [:target, :attribute_name, :attribute_value],
                    :return_value => "0")
    end

    # Create a BIOS configuration job
    #
    # The scheduled job will reboot the server and apply queued BIOS settings.
    # See {#set_attributes}, {#change_boot_source_state}, {#change_boot_order_by_instance_id}
    # for examples of methods that enqueue BIOS changes.
    #
    # @param params [Hash]
    # @option params [String] :target The BIOS FQDD. Usually "BIOS.Setup.1-1".
    # @option params [String] :reboot_job_type "1" or :power_cycle, "2" or :graceful, or "3" or :graceful_with_forced_shutdown
    # @option params [String] :scheduled_start_time Schedules the "configuration job" and the optional "reboot job" at
    #                         the specified start time in the format: yyyymmddhhmmss. A special value of "TIME_NOW"
    #                         schedules the job(s) immediately.
    # @option params [String] :until_time End time for the job execution in format: yyyymmddhhmmss. : If this parameter
    #                         is not NULL, then ScheduledStartTime parameter shall also be specified. NOTE: This
    #                         parameter has a dependency on "ScheduledStartTime" parameter. Both "ScheduledStartTime"
    #                         and "UntilTime" parameters define a time window for scheduling the job(s). After
    #                         scheduling, jobs are executed within the time window.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def create_targeted_config_job(params={})
      client.invoke("CreateTargetedConfigJob", BIOS_SERVICE,
                    :params => params,
                    :required_params => [:target],
                    :optional_params => [:reboot_job_type, :scheduled_start_time, :until_time],
                    :return_value => "4096")
    end

    # Enable or disable a boot source
    #
    # @param params [Hash]
    # @option params [String] :instance_id should be IPL for Initial Program Load, refers to the IPL list (an initial priority list of boot devices)
    # @option params [String] :enabled_state "0" for disabled or "1" for enabled.
    # @option params [String] :source The :instance_id value(s) for {#boot_source_settings} instances to be affected.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def change_boot_source_state(params={})
      client.invoke("ChangeBootSourceState",
                    "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootConfigSetting",
                    :params => params,
                    :required_params => [:enabled_state, :source],
                    :url_params => :instance_id,
                    :return_value => "0")
    end

    # Change boot device order
    #
    # The :source parameter can contain a comma-separated list of {#boot_source_settings}
    # :instance_id values.
    #
    # @note This change is only queued. To actually apply the boot order {#create_targetd_config_job}
    # must be executed. See {#set_boot_order} for a full workflow implementation.
    #
    # @param params [Hash]
    # @option params [String] :instance_id should be IPL for Initial Program Load, refers to the IPL list (an initial priority list of boot devices)
    # @option params [String] :source The :instance_id value(s) for {#boot_source_settings} instances to be affected.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def change_boot_order_by_instance_id(params={})
      client.invoke("ChangeBootOrderByInstanceID",
                    "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_BootConfigSetting",
                    :params => params, :required_params => :source,
                    :url_params => :instance_id,
                    :return_value => ["0", "4096"])
    end

    # Import system configuration XML file
    #
    # Initiates an "import system configuration" job. The server will load the
    # system configuration XML file from the specified remote file share. It
    # will then apply the settings specified in the XML file, rebooting if needed.
    #
    # A server's current XML configuration can be obtained with #{export_system_configuration}.
    #
    # The job progress can be checked with {#get_lc_job}. Once the job is complete
    # a report of all changes that were made or attempted can be found with
    # #{get_config_results}.
    #
    # @note The job will fail if the specified XML file is not valid for the
    # given server. An example of such a case is when the XML configures a device
    # that is not present on the server.
    #
    # @note There are some where the specified configuration cannot be appliaed
    # successfully in a single job execution. In that case the final job status will
    # be "Completed with Errors". In that case the job may be retried and should
    # be able to eventually complete. It should never take more than three tries
    # to either succeed or fail completely.
    #
    # @param params [Hash]
    # @option options [String] :ip_address CIFS or NFS share IPv4 address. For example, 192.168.10.100. Required.
    # @option options [String] :share_name NFS or CIFS network share point. For example, "/home/guest" or "guest_smb.". Required.
    # @option options [String] :file_name The target output file name. Required.
    # @option options [Symbol|String] :share_type share type. "0" or :nfs for NFS and "2" or :cifs for CIFS. Required.
    # @option options [String] :target To identify the component for Import. It identifies the one or more FQDDs.
    #                          Selective list of FQDDs should be given in comma separated format . Default = "All".
    # @option options [Symbol|String] :shutdown_type "0" / :graceful or "1" / :forced
    # @option options [String] :time_to_wait The time to wait for the host to shut down. Default and minimum value is 300 seconds. Maximum value is 3600 seconds.
    # @option options [Symbol|String] :end_host_power_state The final state of the server after the job completes. Can be :on / "0" or :off / "1".
    # @option options [String] :username User name for the target import server.
    # @option options [String] :password Password for the target import server.
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def import_system_configuration_command(params={})
      client.invoke("ImportSystemConfiguration", LC_SERVICE,
                    :params => params,
                    :required_params => [:ip_address, :share_name, :file_name, :share_type],
                    :optional_params => [:target, :shutdown_type, :end_host_power_state, :username, :password],
                    :return_value => "4096")
    end

    # Export system configuration XML file to file share.
    #
    # Initiates a job to export the server system configuration file to a remote
    # file share. The job progress can be monitored with {#get_lc_job}. The resulting
    # configuration file can be applied to another server with {#import_system_configuration_command}.
    #
    # @param params [Hash]
    # @option options [String] :ip_address CIFS or NFS share IPv4 address. For example, 192.168.10.100. Required.
    # @option options [String] :share_name NFS or CIFS network share point. For example, "/home/guest" or "guest_smb.". Required.
    # @option options [String] :file_name The target output file name. Required.
    # @option options [Symbol|String] :share_type share type. "0" or :nfs for NFS and "2" or :cifs for CIFS. Required.
    # @option options [String] :username User name for the target import server.
    # @option options [String] :password Password for the target import server.
    # @option options [String] :workgroup workgroup name, if applicable
    # @option options [String] :target To identify the component for Export. It identifies the one or more FQDDs.
    #                          Selective list of FQDDs should be given in comma separated format . Default = "All".
    # @option options [Symbol|String] :export_use Type of Export intended for use : :default="0", :clone=1, :replace=2.
    # @option options [Symbol|String] :include_in_export Extra information to include in the export:
    #                                 Default (:default=0), Include read only (:read_only= 1),
    #                                 Include password hash values (:password_hash/"2"),
    #                                 Include read only and password hash values (:read_only_and_password_hash/3).
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def export_system_configuration_command(params={})
      client.invoke("ExportSystemConfiguration", LC_SERVICE,
                    :params => params,
                    :required_params => [:ip_address, :share_name, :file_name, :share_type],
                    :optional_params => [:username, :password, :workgroup, :target, :export_use, :include_in_export],
                    :return_value => "4096")
    end

    # Export server LC log to a remote file share.
    #
    # @param params [Hash]
    # @option options [String] :ip_address CIFS or NFS share IPv4 address. For example, 192.168.10.100. Required.
    # @option options [String] :share_name NFS or CIFS network share point. For example, "/home/guest" or "guest_smb.". Required.
    # @option options [String] :file_name The target output file name. Required.
    # @option options [String|Fixnum] :share_type share type. 0 or :nfs for NFS and 2 or :cifs for CIFS. Required.
    # @option options [String] :user_name user name, if applicable.
    # @option options [String] :password password, if applicable
    # @option options [String] :workgroup workgroup name, if applicable
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def export_complete_lc_log(params={})
      client.invoke("ExportCompleteLCLog", LC_SERVICE,
                    :params => params,
                    :required_params => [:ip_address, :share_name, :file_name, :share_type],
                    :optional_params => [:username, :password, :workgroup],
                    :return_value => "4096")
    end

    # Get import system configuration job results.
    #
    # Provides detailed information about system configuration jobs that were
    # attempted during a job initiated by {#import_system_confiugration_command}
    # and whether they succeeded or failed.
    #
    # Unfortunately that data is just provided as big XML blog currently.
    #
    # @param params [Hash]
    # @option options [String] :instance_id The DCIM_LCLogEntry.InstanceID value for the log entry for which the config results is requested. Optional.
    # @option options [String] :job_id This is the jobid for which the config results is requested
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def get_config_results(params={})
      client.invoke("GetConfigResults", LC_RECORD_LOG_SERVICE,
                    :params => params,
                    :optional_params => [:instance_id, :job_id],
                    :return_value => "0")
    end

    # Get deployment job status
    #
    # @param job [String] the job instance id
    # @return [Hash]
    #
    # @example response
    #   {:delete_on_completion => false, :instance_id => "DCIM_OSDConcreteJob:1",
    #    :job_name => "ConnectNetworkISOImage", :job_status => "Success",
    #    :message => "The command was successful", :message_id => "OSD1",
    #    :name => "ConnectNetworkISOImage"}
    def get_deployment_job(job)
      client.get("http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_OSDConcreteJob", job)
    end

    class RetryException < StandardError; end

    # Create reboot job and wait for completion
    #
    # After successful completion the server will be in the process of rebooting.
    #
    # @oaran (see {#create_reboot_job})
    # @return [void]
    def reboot(options={})
      options = {:reboot_job_type => :graceful_with_forced_shutdown,
                 :reboot_start_time => "TIME_NOW",
                 :timeout => 5 * 60}.merge(options)
      poll_for_lc_ready(options)
      logger.info("Rebooting server %s" % host)
      resp = create_reboot_job(options)
      logger.info("Created reboot job %s on %s" % [resp[:reboot_job_id], host])
      setup_job_queue(:job_array => resp[:reboot_job_id], :start_time_interval => "TIME_NOW")
      logger.info("Waiting for reboot job %s to complete on %s" % [resp[:reboot_job_id], host])
      poll_lc_job(resp[:reboot_job_id], :timeout => 15 * 60)
      logger.info("Successfully rebooted %s" % host)
      poll_for_lc_ready(options)
      nil
    end

    # Set the desired server power state.
    #
    # @param options [Hash]
    # @option options [Symbol|String] :requested_state :on / "2" or :off / "13"
    # @return [Hash]
    # @raise [ResponseError] if the command fails
    def set_power_state(params={}) # rubocop:disable Style/AccessorMethodName
      client.invoke("RequestStateChange", POWER_SERVICE,
                    :params => params,
                    :required_params => :requested_state,
                    :return_value => "0")
    end

    # Power the server on.
    #
    # @return [void]
    # @raise [ResponseError] if the command fails
    def power_on
      # Create the reboot job
      logger.debug("Power on server %s" % host)

      power_state = get_power_state
      if power_state != "2"
        set_power_state(:requested_state => :on)
      else
        logger.debug "Server is already powered on"
      end
      nil
    end

    # Power the server off.
    #
    # @return [void]
    # @raise [ResponseError] if the command fails
    def power_off
      # Create the reboot job
      logger.debug("Power off server %s" % host)

      power_state = get_power_state
      if power_state != "13"
        set_power_state(:requested_state => :off)
      else
        logger.debug "Server is already powered off"
      end
    end

    # Check the deployment job status until it is complete or times out
    #
    # @param job [String] the job instance id
    # @return [Hash] the final deployment job status
    def poll_deployment_job(job, options={})
      options = {:timeout => 600}.merge(options)
      max_sleep_secs = 60
      resp = ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep_secs) do
        resp = get_deployment_job(job)
        unless %w(Success Failed).include?(resp[:job_status])
          logger.info("%s status on %s: %s" % [job, host, Parser.response_string(resp)])
          raise(RetryException)
        end
        resp
      end
      raise(ResponseError.new("Deployment job %s failed" % job, resp)) unless resp[:job_status] == "Success"
      resp
    rescue Timeout::Error
      raise(Error, "Timed out waiting for job %s to complete. Final status: %s" % [job, Parser.response_string(resp)])
    end

    # Get LC job status
    #
    # @param job [String] the job instance id
    # @return [Hash]
    #
    # @example response
    #   {:elapsed_time_since_completion=>"132", :instance_id=>"JID_524095646294",
    #    :job_start_time=>"NA", :job_status=>"Completed",
    #    :job_until_time=>"NA", :message=>"Successfully exported system configuration XML file.",
    #    :message_arguments=>"NA", :message_id=>"SYS043",
    #    :name=>"Export Configuration", :percent_complete=>"100"}
    def get_lc_job(job)
      client.get("http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_LifecycleJob", job)
    end

    # Check the LC job status until it is complete or times out
    #
    # @param job [String] the job instance id
    # @return [Hash] the final LC job status
    def poll_lc_job(job, options={})
      options = {:timeout => 900}.merge(options)
      max_sleep_secs = 60
      resp = ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep_secs) do
        resp = get_lc_job(job)
        unless resp[:percent_complete] == "100" || resp[:job_status] =~ /complete/i
          logger.info("%s status on %s: %s" % [job, host, Parser.response_string(resp)])
          raise(RetryException)
        end
        resp
      end
      raise(ResponseError.new("LC job %s failed" % job, resp)) unless resp[:job_status] =~ /complete/i
      resp
    rescue Timeout::Error
      raise(Error, "Timed out waiting for job %s to complete. Final status: %s" % [job, Parser.response_string(resp)])
    end

    # Execute a deployment ISO mount command and await job completion.
    #
    # @param options [Hash] Options not specifically referenced below are passed to the :method command
    # @option options [FixNum] :timeout (5 minutes)
    # @option options [Symbol] :method The WsMan deployment method to execute
    # @return [void]
    def run_deployment_job(options={})
      timeout = options.delete(:timeout) || 5 * 60
      method = options.delete(:method) || raise(ArgumentError, "Missing required method option")
      raise(ArgumentError, "Invalid method option") unless respond_to?(method)

      # LC must be ready for deployment jobs to succeed
      poll_for_lc_ready

      logger.info("Creating %s deployment job with ISO %s on %s" % [method, options[:image_name], host])
      resp = send(method, options)
      logger.info("Initiated %s job %s on %s" % [method, resp[:job], host])
      resp = poll_deployment_job(resp[:job], :timeout => timeout)
      logger.info("%s succeeded with ISO %s on %s: %s" % [method, options[:image_name], host, Parser.response_string(resp)])
      nil
    end

    # Connect network ISO image and await job completion
    #
    # @see {#connect_network_iso_image_command}
    # @param (see {#connect_network_iso_image_command})
    # @return [void]
    def connect_network_iso_image(options={})
      options = {:timeout => 90}.merge(options)
      options[:method] = :connect_network_iso_image_command
      run_deployment_job(options)
    end

    # Connect remote file share ISO image and await job completion
    #
    # @see {#connect_rfs_iso_image_command}
    # @param (see {#connect_network_iso_image_command})
    # @return [void]
    def connect_rfs_iso_image(options={})
      options = {:timeout => 90}.merge(options)
      options[:method] = :connect_rfs_iso_image_command
      resp = rfs_iso_image_connection_info
      if resp[:return_value] == "0"
        logger.info("Disconnecting old RFS ISO %s from %s" % [resp[:file_path], host])
        disconnect_rfs_iso_image
      end

      logger.info("Connecting RFS ISO %s to %s" % [options[:image_name], host])
      run_deployment_job(options)
    end

    # Boot to network ISO image and await job completion
    #
    # @see {#boot_to_network_iso_command}
    # @param options [Hash]
    # @option options [FixNum] :timeout (90 seconds) default timeout
    # @return [Void]
    def boot_to_network_iso_image(options={})
      options = {:timeout => 15 * 60}.merge(options)
      options[:method] = :boot_to_network_iso_command
      run_deployment_job(options)
    end

    # @deprecated Use {boot_to_network_iso_image} instead.
    def self.boot_to_network_iso(endpoint, source_address, logger=nil, image_name="microkernel.iso", share_name="/var/nfs")
      options = {:ip_address => source_address,
                 :image_name => image_name,
                 :share_name => share_name,
                 :share_type => :nfs,
                 :logger => logger}
      WsMan.new(endpoint, :logger => logger).boot_to_network_iso_image(options)
    end

    # Wait for LC to be ready to accept new jobs
    #
    # If the server currently has a network ISO attached, it will be disconnected
    # as that will block LC from becoming ready. Then poll the LC until it
    # reports a ready status.
    #
    # @param options [Hash]
    # @option options [FixNum] :timeout (5 minutes) default timeout
    # @return [Hash]
    def poll_for_lc_ready(options={})
      options = {:timeout => 5 * 60}.merge(options)

      resp = remote_services_api_status
      return if resp[:lcstatus] == "0"

      # If ConnectNetworkISOImage has been executed, LC will be locked until the image is disconnected.
      resp = get_network_iso_image_connection_info
      disconnect_network_iso_image if resp["image_name"]

      # Similarly, if BootToNetworkISO has been executed, LC will be locked until
      # the image is attached. Note that GetAttachStatus will return 1 both for
      # BootToNetworkISO and ConnectNetworkISOImage so it is important to check
      # ConnectNetworkISOImage first.
      resp = get_attach_status
      detach_iso_image if resp["iso_attach_status"] == "1"

      max_sleep_secs = 60
      resp = ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep_secs) do
        resp = remote_services_api_status
        unless resp[:lcstatus] == "0"
          logger.info("LC status on %s: %s" % [host, Parser.response_string(resp)])
          raise(RetryException)
        end
        resp
      end
      logger.info("LC services are ready on %s" % host)
      resp
    rescue Timeout::Error
      raise(Error, "Timed out waiting for LC. Final status: %s" % Parser.response_string(resp))
    end

    # Execute a BIOS configuration job and await completion
    #
    # @param (see {#create_targeted_config_job})
    # @return [void]
    # @raise [ResponseError] if a command fails or the BIOS configuration job fails
    def run_bios_config_job(options={})
      poll_for_lc_ready
      options = {:scheduled_start_time => "TIME_NOW",
                 :reboot_job_type => :graceful_with_forced_shutdown}.merge(options)
      resp = create_targeted_config_job(options)
      logger.info("Initiated BIOS config job %s on %s" % [resp[:job], host])
      resp = poll_lc_job(resp[:job], :timeout => 30 * 60)
      logger.info("Successfully executed BIOS config job %s on %s: %s" % [resp[:job], host, Parser.response_string(resp)])
      logger.info("Waiting for LC ready on %s" % host)
      poll_for_lc_ready
      nil
    end

    # Set BIOS attributes and await job completion
    #
    # @param (see {#set_attributes})
    # @return [void]
    # @raise [ResponseError] if a command fails or the BIOS configuration job fails
    def set_bios_attributes(attributes={}) # rubocop:disable Style/AccessorMethodName
      set_attributes(attributes)
      run_bios_config_job(attributes)
    end

    # Find the specified boot device in {#boot_source_settings}
    #
    # @param [Symbol|String] :hdd for "Hard drive C", :virtual_cd for "Virtual Optical Drive" or the device FQDD such as
    #                        HardDisk.List.1-1, Optical.iDRACVirtual.1-1 or NIC.Slot.2-2-1
    # @return [Hash] the boot device, or nil if not found
    # @raise [ResponseError] if a command fails
    def find_boot_device(boot_device)
      boot_settings = boot_source_settings
      boot_order_map = {:hdd => "HardDisk.List.1-1", :virtual_cd => "Optical.iDRACVirtual.1-1"}
      boot_device = Parser.enum_value("BootDevice", boot_order_map,
                                      boot_device, :strict => false)
      boot_settings.find { |e| e[:instance_id].include?("#%s#" % boot_device) }
    end

    # Set the boot device first in boot order and await completion.
    #
    # After successful execution of the command, the server will be booting
    # the specified boot device.
    #
    # @param [Symbol|String] :hdd for "Hard drive C", :virtual_cd for "Virtual Optical Drive" or the device name itself
    # @param options [Hash]
    # @option params [String] :reboot_job_type "1" or :power_cycle, "2" or :graceful, or "3" or :graceful_with_forced_shutdown
    # @option params [String] :scheduled_start_time Schedules the "configuration job" and the optional "reboot job"
    #                         at the specified start time in the format: yyyymmddhhmmss. A special value of
    #                         "TIME_NOW" schedules the job(s) immediately.
    # @return [void]
    # @raise [ResponseError] if a command fails
    def set_boot_order(boot_device, options={})
      options = {:scheduled_start_time => "TIME_NOW",
                 :reboot_job_type => :graceful_with_forced_shutdown}.merge(options)

      logger.info("Waiting for LC ready on %s" % host)
      poll_for_lc_ready
      boot_mode = bios_enumerations.find { |e| e[:attribute_name] == "BootMode" }
      raise("BootMode not found") unless boot_mode

      unless boot_mode[:current_value] == "Bios"
        # Set back to bios boot mode
        logger.info("Current boot mode on %s is %s, resetting to Bios BootMode" %
                        [host, boot_mode[:current_value]])
        set_bios_attributes(:target => boot_mode[:fqdd], :attribute_name => "BootMode",
                            :attribute_value => "Bios")
      end

      target = find_boot_device(boot_device)
      unless target
        raise("Could not find %s boot device in current list: %s" %
                  [boot_device, boot_source_settings.map { |e| e[:element_name] }.join(", ")])
      end

      if target[:current_assigned_sequence] == "0" && target[:current_enabled_status] == "1"
        logger.info("%s is already configured to boot from %s" % [host, target[:element_name]])
        return
      end

      change_boot_order_by_instance_id(:instance_id => "IPL",
                                       :source => target[:instance_id])
      change_boot_source_state(:instance_id => "IPL", :enabled_state => "1",
                               :source => target[:instance_id])
      run_bios_config_job(:target => boot_mode[:fqdd],
                          :scheduled_start_time => options[:scheduled_start_time],
                          :reboot_job_type => options[:reboot_job_type])
    end

    # Connect the remote file system ISO and boot it
    #
    # After successful execution of the command, the server will boot the ISO.
    # The ISO will be first in the boot sequence.
    #
    # @note {#disconnect_rfs_iso_image} should be called as soon as the ISO is not needed.
    #
    # @param options [Hash]
    # @option options [String] :ip_address CIFS or NFS share IPv4 address. For example, 192.168.10.100. Required.
    # @option options [String] :share_name NFS or CIFS network share point. For example, "/home/guest" or "guest_smb.". Required.
    # @option options [String] :image_name ISO image name. Required.
    # @option options [String|Fixnum] :share_type share type. 0 or :nfs for NFS and 2 or :cifs for CIFS. Required.
    # @option options [String] :workgroup workgroup name, if applicable
    # @option options [String] :user_name user name, if applicable.
    # @option options [String] :password password, if applicable
    # @option options [String] :hash_type type of hash algorithm used to compute checksum: 1 or :md5 for MD5 and 2 or :sha1 for SHA1
    # @option options [String] :hash_value checksum value in string format computed using HashType algorithm
    # @option options [String] :auto_connect auto-connect to ISO image up on iDRAC reset
    # @option params [String] :reboot_job_type "1" or :power_cycle, "2" or :graceful, or "3" or :graceful_with_forced_shutdown
    # @option params [String] :reboot_start_time Schedules the "reboot job" at the specified start time in the
    #                         format: yyyymmddhhmmss. A special value of "TIME_NOW" schedules the job(s) immediately.
    # @option params [FixNum] :timeout (600) The number of seconds to wait for the virtual CD to become available
    # @return [void]
    # @raise [ResponseError] if a command fails
    def boot_rfs_iso_image(options={})
      options = {:reboot_job_type => :graceful_with_forced_shutdown,
                 :reboot_start_time => "TIME_NOW",
                 :timeout => 10 * 60}.merge(options)
      connect_rfs_iso_image(options)

      # Have to reboot in order for virtual cd to show up in boot source settings
      reboot(options)

      # Wait for virtual cd to show up in boot source settings
      max_sleep = 60
      ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep) do
        find_boot_device(:virtual_cd) || raise(RetryException)
      end

      set_boot_order(:virtual_cd, options)

    rescue Timeout::Error
      raise(Error, "Timed out waiting for virtual CD to become available on %s" % host)
    end

    # @deprecated Use {poll_for_lc_ready} instead.
    def self.wait_for_lc_ready(endpoint, logger=nil, attempts=0, max_attempts=30)
      if attempts > max_attempts
        raise(Error, "Life cycle controller is busy")
      else
        status = lcstatus(endpoint, logger).to_i
        if status == 0
          return
        else
          logger.debug "LC status is busy: status code #{status}. Waiting..." if logger
          sleep sleep_time
          wait_for_lc_ready(endpoint, logger, attempts + 1, max_attempts)
        end
      end
    end

    def self.sleep_time
      60
    end
  end
end
