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
    DEPLOYMENT_SERVICE_SCHEMA = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_OSDeploymentService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_OSDeploymentService,SystemName=DCIM:ComputerSystem,Name=DCIM:OSDeploymentService"
    JOB_SERVICE_SCHEMA = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_JobService?CreationClassName=DCIM_JobService,Name=JobService,SystemName=Idrac,SystemCreationClassName=DCIM_ComputerSystem"
    LC_SERVICE_SCHEMA = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_LCService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_LCService,SystemName=DCIM:ComputerSystem,Name=DCIM:LCService"
    SOFTWARE_INSTALLATION_SERVICE_SCHEMA = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_SoftwareInstallationService?CreationClassName=DCIM_SoftwareInstallationService,SystemCreationClassName=DCIM_ComputerSystem,SystemName=IDRAC:ID,Name=SoftwareUpdate"
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

    def self.reboot(endpoint, logger=nil)
      # Create the reboot job
      logger.debug("Rebooting server #{endpoint[:host]}") if logger
      instanceid = invoke(endpoint,
                          "CreateRebootJob",
                          SOFTWARE_INSTALLATION_SERVICE_SCHEMA,
                          :selector => '//wsman:Selector Name="InstanceID"',
                          :props => {"RebootJobType" => "1"},
                          :logger => logger)

      # Execute job
      jobmessage = invoke(endpoint,
                          "SetupJobQueue",
                          JOB_SERVICE_SCHEMA,
                          :selector => "//n1:Message",
                          :props => {
                            "JobArray" => instanceid,
                            "StartTimeInterval" => "TIME_NOW"
                          },
                          :logger => logger)
      logger.debug "Job Message #{jobmessage}" if logger
      true
    end

    def self.poweroff(endpoint, logger=nil)
      # Create the reboot job
      logger.debug("Power off server #{endpoint[:host]}") if logger

      power_state = get_power_state(endpoint, logger)
      if power_state.to_i != 13
        invoke(endpoint,
               "RequestStateChange",
               "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_ComputerSystem?CreationClassName=DCIM_ComputerSystem,Name=srv:system",
               :props => {"RequestedState" => "3"},
               :logger => logger)
      else
        logger.debug "Server is already powered off" if logger
      end
      true
    end

    def self.poweron(endpoint, logger=nil)
      # Create the reboot job
      logger.debug("Power on server #{endpoint[:host]}") if logger

      power_state = get_power_state(endpoint, logger)
      if power_state.to_i != 2
        invoke(endpoint,
               "RequestStateChange",
               "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_ComputerSystem?CreationClassName=DCIM_ComputerSystem,Name=srv:system",
               :props => {"RequestedState" => "2"},
               :logger => logger)
      else
        logger.debug "Server is already powered on" if logger
      end
      true
    end

    def self.get_power_state(endpoint, logger=nil)
      # Create the reboot job
      logger.debug("Getting the power state of the server with iDRAC IP: #{endpoint[:host]}") if logger
      response = invoke(endpoint,
                        "enumerate",
                        "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_CSAssociatedPowerManagementService",
                        :logger => logger)
      updated_xml = response.scan(%r{(<\?xml.*?</s:Envelope>?)}m)
      xmldoc = REXML::Document.new(updated_xml[1][0])
      powerstate_node = REXML::XPath.first(xmldoc, "//n1:PowerState")
      powerstate = powerstate_node.text
      logger.debug("Power State: #{powerstate}") if logger
      powerstate
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
      invoke(endpoint, "GetRemoteServicesAPIStatus", LC_SERVICE_SCHEMA, :selector => "//n1:LCStatus", :logger => logger)
    end

    # Get the lifecycle controller (LC) status
    #
    # @example ready response
    #   {:lcstatus=>"0", :message=>"Lifecycle Controller Remote Services is ready.",
    #    :message_id=>"LC061", :rtstatus=>"0", :return_value=>"0", :server_status=>"2", :status=>"0"}
    #
    # @example busy response
    #   {:lcstatus=>"5", :message=>"Lifecycle Controller Remote Services is not ready.",
    #    :message_id=>"LC060", :rtstatus=>"1", :return_value=>"0", :server_status=>"1", :status=>"1"}
    #
    # An lcstatus of "0" indicates that the LC is ready to accept new jobs.
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @option options [Hash] :logger
    # @return [Hash]
    def remote_services_api_status
      client.invoke("GetRemoteServicesAPIStatus", LC_SERVICE)
    end

    # Reboot server to a network ISO
    #
    # @note {detach_iso_image} should be called once the ISO is no longer needed.
    # @param options [Hash]
    # @option options [Logger] :logger a logger to use
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
      client.invoke("BootToNetworkISO", DEPLOYMENT_SERVICE_SCHEMA,
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
      client.invoke("ConnectNetworkISOImage", DEPLOYMENT_SERVICE_SCHEMA,
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
      client.invoke("DetachISOImage", DEPLOYMENT_SERVICE_SCHEMA, :return_value => "0")
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
      client.invoke("DisconnectNetworkISOImage", DEPLOYMENT_SERVICE_SCHEMA, :return_value => "0")
    end

    # Get current drivers and ISO connection status
    #
    # @example response
    #   {:drivers_attach_status=>"0", :iso_attach_status=>"1", :return_value=>"0"}
    #
    # The drivers and iso attach status will be reported as "0" for not attached
    # and "1" for "attached". The overall return_value will be non-zero if nothing
    # is currently attached.
    #
    # The ISO will show as attached if either {boot_to_network_iso_command} or
    # {connect_network_iso_image_command} have been executed.
    #
    # @return [Hash]
    def get_attach_status # rubocop:disable Style/AccessorMethodName
      client.invoke("GetAttachStatus", DEPLOYMENT_SERVICE_SCHEMA)
    end

    # Get ISO image connection info
    #
    # @example response
    #   {:host_attached_status=>"1", :host_booted_from_iso=>"1",
    #    :ipaddr=>"172.25.3.100", :iso_connection_status=>"1",
    #    :image_name=>"ipxe.iso", :return_value=>"0", :share_name=>"/var/nfs"}
    #
    # The ISO attach status will be "0" for not attached and "1" for attached.
    #
    # The ISO will show as attached only if the {connect_network_iso_image_command}
    # has been executed.
    #
    # @return [Hash]
    # @raise [ResponseError] if the command does not succeed
    def get_network_iso_image_connection_info # rubocop:disable Style/AccessorMethodName
      client.invoke("GetNetworkISOConnectionInfo", DEPLOYMENT_SERVICE_SCHEMA)
    end

    # Get deployment job status
    #
    # @example response
    #   {:delete_on_completion => false, :instance_id => "DCIM_OSDConcreteJob:1",
    #    :job_name => "ConnectNetworkISOImage", :job_status => "Success",
    #    :message => "The command was successful", :message_id => "OSD1",
    #    :name => "ConnectNetworkISOImage"}
    #
    # @param job [String] the job instance id
    # @return [Hash]
    def get_deployment_job(job)
      client.get("http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_OSDConcreteJob", job)
    end

    class RetryException < StandardError; end

    # Check the deployment job status until it is complete or times out
    #
    # @param job [String] the job instance id
    # @return [Hash]
    def poll_deployment_job(job, options={})
      options = {:logger => Logger.new(nil), :timeout => 600}.merge(options)
      max_sleep_secs = 60
      resp = ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep_secs) do
        resp = get_deployment_job(job)
        unless %w(Success Failed).include?(resp[:job_status])
          options[:logger].info("%s status on %s: %s" % [job, host, Parser.response_string(resp)])
          raise(RetryException)
        end
        resp
      end
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
      raise(ResponseError.new("%s job %s failed" % [method, resp[:job]], resp)) unless resp[:job_status] == "Success"
      logger.info("%s succeeded with ISO %s on %s: %s" % [method, options[:image_name], host, Parser.response_string(resp)])
      nil
    end

    # Connect network ISO image and await job completion
    #
    # @see {#connect_network_iso_image_command}
    # @param options [Hash]
    # @option options [FixNum] :timeout (90 seconds) default timeout
    # @return [void]
    def connect_network_iso_image(options={})
      options = {:timeout => 90}.merge(options)
      options[:method] = :connect_network_iso_image_command
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
