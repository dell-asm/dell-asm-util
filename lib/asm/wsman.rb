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
    def self.get_lc_status(endpoint, options={})
      logger = options[:logger] || Logger.new(nil)
      resp = invoke(endpoint, "GetRemoteServicesAPIStatus", LC_SERVICE_SCHEMA, :logger => logger)
      parse(resp)
    end

    # Invoke a deployment ISO command
    #
    # DCIM_OSDeploymentService includes several commands that operate on ISO
    # images hosted on network shares that take the same parameters.
    #
    # @api private
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param command [String] the deployment command
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
    def self.osd_deployment_invoke_iso(endpoint, command, options={})
      options = options.dup
      required_api_params = [:ip_address, :share_name, :share_type, :image_name]
      optional_api_params = [:workgroup, :user_name, :password, :hash_type, :hash_value, :auto_connect]
      missing_params = required_api_params.reject { |k| options.include?(k) }
      raise("Missing required parameter(s): %s" % missing_params.join(", ")) unless missing_params.empty?

      logger = options.delete(:logger)
      options.reject! { |k| !(required_api_params + optional_api_params).include?(k) }

      props = options.keys.inject({}) do |acc, key|
        acc[param_key(key)] = wsman_value(key, options[key])
        acc
      end
      resp = invoke(endpoint, command, DEPLOYMENT_SERVICE_SCHEMA, :logger => logger, :props => props)
      ret = parse(resp)
      raise(ResponseError.new("%s failed" % command, ret)) unless ret[:return_value] == "4096"
      ret
    end

    # Reboot server to a network ISO
    #
    # @note {detach_iso_image} should be called once the ISO is no longer needed.
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash] the ISO parameters. See {osd_deployment_invoke_iso} options hash.
    # @raise [ResponseError] if the command fails
    def self.boot_to_network_iso_command(endpoint, options={})
      osd_deployment_invoke_iso(endpoint, "BootToNetworkISO", options)
    end

    # Connect a network ISO as a virtual CD-ROM
    #
    # The normal server boot order will be ignored after this call has been made.
    # The server will only boot into the network ISO until {disconnect_network_iso_image}
    # is called. The LC controller will be locked while the server is in this
    # state and no other LC jobs can be run.
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash] the ISO parameters. See {osd_deployment_invoke_iso} options hash.
    # @raise [ResponseError] if the command fails
    def self.connect_network_iso_image_command(endpoint, options={})
      osd_deployment_invoke_iso(endpoint, "ConnectNetworkISOImage", options)
    end

    # Invoke a DCIM_DeploymentService command
    #
    # @api private
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param command [String]
    # @param options [Hash]
    # @option options [String] :return_value Expected ws-man return_value. An exception will be raised if this is not returned.
    # @return [Hash]
    def self.deployment_invoke(endpoint, command, options={})
      resp = invoke(endpoint, command, DEPLOYMENT_SERVICE_SCHEMA, :logger => options[:logger])
      ret = parse(resp)
      if options[:return_value] && ret[:return_value] != options[:return_value]
        raise(ResponseError.new("%s failed" % command, ret))
      end
      ret
    end

    # Detach an ISO that was mounted with {boot_to_network_iso_command}
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash]
    # @option options [Logger] :logger
    # @return [Hash]
    def self.detach_iso_image(endpoint, options={})
      options = options.merge(:return_value => "0")
      deployment_invoke(endpoint, "DetachISOImage", options)
    end

    # @deprecated Use {detach_iso_image} instead.
    def self.detach_network_iso(endpoint, logger=nil)
      detach_iso_image(endpoint, :logger => logger)
    end

    # Disconnect an ISO that was mounted with {connect_network_iso_image_command}
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash]
    # @option options [Logger] :logger
    # @return [Hash]
    def self.disconnect_network_iso_image(endpoint, options={})
      options = options.merge(:return_value => "0")
      deployment_invoke(endpoint, "DisconnectNetworkISOImage", options)
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
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash]
    # @option options [Logger] :logger
    # @return [Hash]
    def self.get_attach_status(endpoint, options={})
      deployment_invoke(endpoint, "GetAttachStatus", options)
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
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash]
    # @option options [Logger] :logger
    # @return [Hash]
    def self.get_network_iso_image_connection_info(endpoint, options={})
      deployment_invoke(endpoint, "GetNetworkISOConnectionInfo", options)
    end

    # Get deployment job status
    #
    # @example response
    #   {:delete_on_completion => false, :instance_id => "DCIM_OSDConcreteJob:1",
    #    :job_name => "ConnectNetworkISOImage", :job_status => "Success",
    #    :message => "The command was successful", :message_id => "OSD1",
    #    :name => "ConnectNetworkISOImage"}
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param job [String] the job instance id
    # @param options [Hash]
    # @option options [Logger] :logger
    # @return [Hash]
    def self.get_deployment_job(endpoint, job, options={})
      url = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_OSDConcreteJob?InstanceID=%s" % job
      parse(invoke(endpoint, "get", url, :logger => options[:logger]))
    end

    class RetryException < StandardError; end

    # Check the deployment job status until it is complete or times out
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param job [String] the job instance id
    # @param options [Hash]
    # @option options [Logger] :logger
    # @return [Hash]
    def self.poll_deployment_job(endpoint, job, options={})
      options = {:logger => Logger.new(nil), :timeout => 600}.merge(options)
      max_sleep_secs = 60
      resp = ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep_secs) do
        resp = get_deployment_job(endpoint, job, :logger => options[:logger])
        unless %w(Success Failed).include?(resp[:job_status])
          options[:logger].info("%s status on %s: %s" % [job, endpoint[:host], Parser.response_string(resp)])
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
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param command [String] the ISO command, e.g. BootToNetworkISO or ConnectNetworkISOImage
    # @param job [String] the job instance id
    # @param options [Hash]
    # @option options [Logger] :logger
    # @option options [FixNum] :timeout (5 minutes)
    # @return [Hash]
    def self.run_deployment_job(endpoint, command, options={})
      options = {:timeout => 5 * 60}.merge(options)
      logger = options[:logger] || Logger.new(nil)

      # LC must be ready for deployment jobs to succeed
      poll_for_lc_ready(endpoint, :logger => logger)

      logger.info("Invoking %s with ISO %s on %s" % [command, options[:image_name], endpoint[:host]])
      resp = osd_deployment_invoke_iso(endpoint, command, options)
      logger.info("Initiated %s job %s on %s" % [command, resp[:job], endpoint[:host]])
      resp = poll_deployment_job(endpoint, resp[:job], options)
      raise(ResponseError.new("%s job %s failed" % [command, resp[:job]], resp)) unless resp[:job_status] == "Success"
      logger.info("%s succeeded with ISO %s on %s: %s" % [command, options[:image_name], endpoint[:host], Parser.response_string(resp)])
    end

    # Connect network ISO image and await job completion
    #
    # @see {connect_network_iso_image_command}
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash]
    # @option options [Logger] :logger
    # @option options [FixNum] :timeout (5 minutes)
    # @return [Hash]
    def self.connect_network_iso_image(endpoint, options={})
      options = {:timeout => 90}.merge(options)
      run_deployment_job(endpoint, "ConnectNetworkISOImage", options)
    end

    # Boot to network ISO image and await job completion
    #
    # @see boot_to_network_iso_command
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @option options [Logger] :logger
    # @option options [FixNum] :timeout (5 minutes)
    # @return [Hash]
    def self.boot_to_network_iso_image(endpoint, options={})
      options = {:timeout => 15 * 60}.merge(options)
      run_deployment_job(endpoint, "BootToNetworkISO", options)
    end

    # @deprecated Use {boot_to_network_iso_image} instead.
    def self.boot_to_network_iso(endpoint, source_address, logger=nil, image_name="microkernel.iso", share_name="/var/nfs")
      options = {:ip_address => source_address,
                 :image_name => image_name,
                 :share_name => share_name,
                 :share_type => :nfs,
                 :logger => logger}
      boot_to_network_iso_image(endpoint, options)
    end

    # Wait for LC to be ready to accept new jobs
    #
    # If the server currently has a network ISO attached, it will be disconnected
    # as that will block LC from becoming ready. Then poll the LC until it
    # reports a ready status.
    #
    # @param endpoint [Hash] the server connection details. See {invoke} endpoint hash.
    # @param options [Hash]
    # @option options [Logger] :logger
    # @option options [FixNum] :timeout (5 minutes)
    # @return [Hash]
    def self.poll_for_lc_ready(endpoint, options={})
      resp = get_lc_status(endpoint, :logger => options[:logger])
      return if resp[:lcstatus] == "0"

      # If ConnectNetworkISOImage has been executed, LC will be locked until the image is disconnected.
      resp = get_network_iso_image_connection_info(endpoint, :logger => logger)
      disconnect_network_iso_image(endpoint, options) if resp["image_name"]

      # Similarly, if BootToNetworkISO has been executed, LC will be locked until
      # the image is attached. Note that GetAttachStatus will return 1 both for
      # BootToNetworkISO and ConnectNetworkISOImage so it is important to check
      # ConnectNetworkISOImage first.
      resp = get_attach_status(endpoint, options)
      detach_iso_image(endpoint, options) if resp["iso_attach_status"] == "1"

      options = {:logger => Logger.new(nil), :timeout => 5 * 60}.merge(options)
      max_sleep_secs = 60
      resp = ASM::Util.block_and_retry_until_ready(options[:timeout], RetryException, max_sleep_secs) do
        resp = get_lc_status(endpoint, :logger => options[:logger])
        unless resp[:lcstatus] == "0"
          options[:logger].info("LC status on %s: %s" % [endpoint[:host], Parser.response_string(resp)])
          raise(RetryException)
        end
        resp
      end
      options[:logger].info("LC services are ready on %s" % endpoint[:host])
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
