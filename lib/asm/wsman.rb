require 'pathname'
require 'asm/util'
require 'rexml/document'
require 'hashie'

module ASM
  module WsMan

    class Error < StandardError; end

    DEPLOYMENT_SERVICE_SCHEMA = 'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_OSDeploymentService?SystemCreationClassName="DCIM_ComputerSystem",CreationClassName="DCIM_OSDeploymentService",SystemName="DCIM:ComputerSystem",Name="DCIM:OSDeploymentService"'

    # Wrapper for the wsman client. endpoint should be a hash of
    # :host, :user, :password
    def self.invoke(endpoint, method, schema, options = {})
      options = {
        :selector => nil,
        :props => {},
        :input_file => nil,
        :logger => nil,
        :nth_attempt => 0,
      }.merge(options)

      unless options[:logger].nil? || options[:logger].respond_to?(:error)
        # The Puppet class has most of the methods loggers respond to except for error
        logger = options[:logger]
        def logger.error(msg)
          self.err(msg)
        end
      end

      if %w(enumerate get).include?(method)
        args = [method, schema]
      else
        args = ['invoke', '-a', method, schema]
      end

      args += [ '-h', endpoint[:host],
        '-V', '-v', '-c', 'dummy.cert', '-P', '443',
        '-u', endpoint[:user],
        '-j', 'utf-8', '-m', '256', '-y', 'basic', '--transport-timeout=300' ]
      if options[:input_file]
        args += [ '-J', options[:input_file] ]
      end
      options[:props].each do |key, val|
        args += [ '-k', "#{key}=#{val}" ]
      end

      if options[:logger]
        options[:logger].debug("Executing wsman #{args.join(' ')}")
      end
      result = ASM::Util.run_command_with_args('env', "WSMAN_PASS=#{endpoint[:password]}",
                                               'wsman', '--non-interactive', *args)
      options[:logger].debug("Result = #{result}") if options[:logger]

      # The wsman cli does not set exit_status properly on failure, so we
      # have to check stderr as well...
      unless result.exit_status == 0 && result.stderr.empty?
        if result['stdout'] =~ /Authentication failed/
          if options[:nth_attempt] < 2
            # We have seen sporadic authentication failed errors from idrac. Retry a couple times
            options[:nth_attempt] += 1
            options[:logger].info("Authentication failed, retrying #{endpoint[:host]}...") if options[:logger]
            sleep 10
            return invoke(endpoint, method, schema, options)
          end
          msg = "Authentication failed, please retry with correct credentials after resetting the iDrac at #{endpoint[:host]}."
        elsif result['stdout'] =~ /Connection failed./ || result['stderr'] =~ /Connection failed./
          if options[:nth_attempt] < 2
            # We have seen sporadic connection failed errors from idrac. Retry a couple times
            options[:nth_attempt] += 1
            options[:logger].info("Connection failed, retrying #{endpoint[:host]}...") if options[:logger]
            sleep 10
            return invoke(endpoint, method, schema, options)
          end
          msg = "Connection failed, Couldn't connect to server. Please check IP address credentials for iDrac at #{endpoint[:host]}."
        else
          msg = "Failed to execute wsman command against server #{endpoint[:host]}"
        end
        options[:logger].error(msg) if options[:logger]
        raise(Error, "#{msg}: #{result}")
      end

      if options[:selector]
        doc = REXML::Document.new(result['stdout'])
        options[:selector] = [options[:selector]] unless options[:selector].respond_to?(:collect)
        ret = options[:selector].collect do |selector|
          node = REXML::XPath.first(doc, selector)
          if node
            node.text
          else
            msg = "Invalid WS-MAN response from server #{endpoint[:host]}"
            options[:logger].error(msg) if options[:logger]
            raise(Error, msg)
          end
        end
        ret.size == 1 ? ret.first : ret
      else
        result['stdout']
      end
    end

    def self.reboot(endpoint, logger = nil)
      # Create the reboot job
      logger.debug("Rebooting server #{endpoint[:host]}") if logger
      instanceid = invoke(endpoint,
      'CreateRebootJob',
      'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_SoftwareInstallationService?CreationClassName=DCIM_SoftwareInstallationService,SystemCreationClassName=DCIM_ComputerSystem,SystemName=IDRAC:ID,Name=SoftwareUpdate',
      :selector =>'//wsman:Selector Name="InstanceID"',
      :props => { 'RebootJobType' => '1' },
      :logger => logger)

      # Execute job
      jobmessage = invoke(endpoint,
      'SetupJobQueue',
      'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_JobService?CreationClassName=DCIM_JobService,Name=JobService,SystemName=Idrac,SystemCreationClassName=DCIM_ComputerSystem',
      :selector => '//n1:Message',
      :props => {
        'JobArray' => instanceid,
        'StartTimeInterval' => 'TIME_NOW'
      },
      :logger => logger)
      logger.debug "Job Message #{jobmessage}" if logger
      return true
    end

    def self.poweroff(endpoint, logger = nil)
      # Create the reboot job
      logger.debug("Power off server #{endpoint[:host]}") if logger

      power_state = get_power_state(endpoint, logger)
      if power_state.to_i != 13
        response = invoke(endpoint, 'RequestStateChange',
        'http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_ComputerSystem?CreationClassName=DCIM_ComputerSystem,Name=srv:system',
        :props => { 'RequestedState' => "3"} ,
        :logger => logger)
      else
        logger.debug "Server is already powered off" if logger
      end
      return true
    end

    def self.get_power_state(endpoint, logger = nil)
      # Create the reboot job
      logger.debug("Getting the power state of the server with iDRAC IP: #{endpoint[:host]}") if logger
      response = invoke(endpoint,
      'enumerate',
      'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_CSAssociatedPowerManagementService',
      :logger => logger)
      updated_xml = match_array=response.scan(/(<\?xml.*?<\/s:Envelope>?)/m)
      xmldoc = REXML::Document.new(updated_xml[1][0])
      powerstate_node = REXML::XPath.first(xmldoc, '//n1:PowerState')
      powerstate = powerstate_node.text
      logger.debug("Power State: #{powerstate}") if logger
      powerstate
    end

    def self.get_wwpns(endpoint, logger = nil)
      wsmanCmdResponse = invoke(endpoint, 'enumerate',
      'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/DCIM/DCIM_FCView',
      :logger => logger)
      wsmanCmdResponse.split(/\n/).collect do |ele|
        if ele =~ /<n1:VirtualWWPN>(\S+)<\/n1:VirtualWWPN>/
          $1
        end
      end.compact
    end

    # Returns true if the NIC can be used in an ASM deployment, false otherwise.
    #
    # Criteria are:
    #
    # 1. NICs are excluded it their PermanentMACAddress is nil. Recent NIC / iDrac
    #    firmwares have started returning disabled NICs in the nic_view data, but
    #    their PermanentMACAddress will be nil.
    # 2. FQDD includes Embedded. Embedded NICs are not supported unless they are 57810
    # 3. Product is Broadcom 57800. These are 2x10Gb, 2x1Gb NICs
    # 4. NIC is not disabled in the BIOS.
    def self.is_usable_nic?(nic_info,bios_info)
      unsupported_embedded = nic_info['FQDD'].include?('Embedded') && !nic_info['ProductName'].include?('57810')
      !nic_info['PermanentMACAddress'].nil? &&
          !unsupported_embedded &&
          !nic_info['ProductName'].match(/(Broadcom|QLogic).*5720/) &&
              !nic_status(nic_info['FQDD'],bios_info).match(/disabled/i)
    end

    def self.nic_status(fqdd,bios_info)
      fqdd_display = bios_display_name(fqdd)
      nic_enabled = 'Enabled'
      bios_info.each do |bios_ele|
        if bios_ele['AttributeDisplayName'] == fqdd_display
          nic_enabled = bios_ele['CurrentValue']
          break
        end
      end
      nic_enabled
    end

    def self.bios_display_name(fqdd)
      display_name = fqdd
      fqdd_info = fqdd.scan(/NIC.(\S+)\.(\S+)-(\d+)-(\d+)/).flatten
      case fqdd_info[0]
        when 'Mezzanine'
          display_name = "Mezzanine Slot #{fqdd_info[1]}"
        when 'Integrated'
          display_name = "Integrated Network Card 1"
        when 'Slot'
          display_name = "Slot #{fqdd_info[1]}"
        else
      end
      display_name
    end

    # Return all the server MAC Address along with the interface location
    # in a hash format
    def self.get_mac_addresses(endpoint, logger = nil)
      bios_info = get_bios_enumeration(endpoint,logger)
      ret = get_nic_view(endpoint, logger).inject({}) do |result, element|
        result[element['FQDD']] = element['CurrentMACAddress'] if is_usable_nic?(element,bios_info)
        result
      end
      logger.debug("********* MAC Address List is #{ret.inspect} **************") if logger
      ret
    end

    def self.get_permanent_mac_addresses(endpoint, logger = nil)
      bios_info = get_bios_enumeration(endpoint,logger)
      ret = get_nic_view(endpoint, logger).inject({}) do |result, element|
        unless element['FQDD'].include?('Embedded')
          result[element['FQDD']] = element['PermanentMACAddress'] if is_usable_nic?(element,bios_info)
        end
        result
      end
      logger.debug("********* MAC Address List is #{ret.inspect} **************") if logger
      ret
    end

    # Gets Nic View data
    def self.get_nic_view(endpoint, logger = nil, tries = 0)
      mac_info = {}
      resp = invoke(endpoint, 'enumerate',
      'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_NICView',
      :logger => logger)
      nic_views = resp.split("<n1:DCIM_NICView>")
      nic_views.shift
      ret = nic_views.collect do |nic_view|
        nic_view.split("\n").inject({}) do |ret, line|
          if line =~ /<n1:(\S+).*>(.*)<\/n1:\S+>/
            ret[$1] = $2
          elsif line =~ /<n1:(\S+).*\/>/
            ret[$1] = nil
          end
          ret
        end
      end

      # Apparently we sometimes see a spurious empty return value...
      if ret.empty? && tries == 0
        ret = get_nic_view(endpoint, logger, tries + 1)
      end
      ret
    end

    # Gets Nic View data
    def self.get_bios_enumeration(endpoint, logger = nil)
      mac_info = {}
      resp = invoke(endpoint, 'enumerate',
                    'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_BIOSEnumeration',
                    :logger => logger)
      bios_enumeration = resp.split("<n1:DCIM_BIOSEnumeration>")
      bios_enumeration.shift
      bios_enumeration.collect do |bios_view|
        bios_view.split("\n").inject({}) do |ret, line|
          if line =~ /<n1:(\S+).*>(.*)<\/n1:\S+>/
            ret[$1] = $2
          elsif line =~ /<n1:(\S+).*\/>/
            ret[$1] = nil
          end
          ret
        end
      end
    end

    #Gets Nic View data for a specified fqdd
    def self.get_fcoe_wwpn(endpoint, logger = nil)
      fcoe_info = {}
      resp = invoke(endpoint, 'enumerate',
      'http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_NICView',
      :logger => logger)
      nic_views = resp.split("<n1:DCIM_NICView>")
      nic_views.shift
      nic_views.each do |nic_view|
        nic_name = nil
        nic_view.split("\n").each do |line|
          if line =~ /<n1:FQDD>(\S+)<\/n1:FQDD>/
            nic_name = $1
            fcoe_info[nic_name] = {}
          end
        end
        nic_view.split("\n").each do |line|
          if line =~ /<n1:FCoEWWNN>(\S+)<\/n1:FCoEWWNN>/
            fcoe_wwnn = $1
            fcoe_info[nic_name]['fcoe_wwnn'] = fcoe_wwnn
          end

          if line =~ /<n1:PermanentFCOEMACAddress>(\S+)<\/n1:PermanentFCOEMACAddress>/
            fcoe_permanent_fcoe_macaddress = $1
            fcoe_info[nic_name]['fcoe_permanent_fcoe_macaddress'] = fcoe_permanent_fcoe_macaddress
          end

          if line =~ /<n1:FCoEOffloadMode>(\S+)<\/n1:FCoEOffloadMode>/
            fcoe_offload_mode = $1
            fcoe_info[nic_name]['fcoe_offload_mode'] = fcoe_offload_mode
          end

          if line =~ /<n1:VirtWWN>(\S+)<\/n1:VirtWWN>/
            virt_wwn = $1
            fcoe_info[nic_name]['virt_wwn'] = virt_wwn
          end

          if line =~ /<n1:VirtWWPN>(\S+)<\/n1:VirtWWPN>/
            virt_wwpn = $1
            fcoe_info[nic_name]['virt_wwpn'] = virt_wwpn
          end

          if line =~ /<n1:WWN>(\S+)<\/n1:WWN>/
            wwn = $1
            fcoe_info[nic_name]['wwn'] = wwn
          end

          if line =~ /<n1:WWPN>(\S+)<\/n1:WWPN>/
            wwpn = $1
            fcoe_info[nic_name]['wwpn'] = wwpn
          end

        end
      end

      # Remove the Embedded NICs from the list
      fcoe_info.keys.each do |nic_name|
        fcoe_info.delete(nic_name) if nic_name.include?('Embedded')
      end

      logger.debug("FCoE info: #{fcoe_info.inspect} **************") if logger
      fcoe_info
    end

    #Gets LC status
    def self.lcstatus (endpoint, logger = nil)
      invoke(endpoint, 'GetRemoteServicesAPIStatus','http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_LCService?SystemCreationClassName="DCIM_ComputerSystem",CreationClassName="DCIM_LCService",SystemName="DCIM:ComputerSystem",Name="DCIM:LCService"', :selector => '//n1:LCStatus', :logger => logger)
    end

    def self.detach_network_iso(endpoint, logger = nil)
      invoke(endpoint, 'DetachISOImage', DEPLOYMENT_SERVICE_SCHEMA, :logger => logger)
    end

    def self.boot_to_network_iso (endpoint, source_address, logger = nil, image_name = 'microkernel.iso', share_name = '/var/nfs')
      # If an ISO is attached it must be detached or the server will boot off the old ISO
      detach_network_iso(endpoint, logger)

      # LC must be ready for BootToNetworkISO to succeed
      wait_for_lc_ready(endpoint, logger)

      props = {'IPAddress' => source_address,
               'ShareName' => share_name,
               'ShareType' => 0,
               'ImageName' => image_name }
      resp = invoke(endpoint, 'BootToNetworkISO', DEPLOYMENT_SERVICE_SCHEMA,
                    :logger => logger, :props => props, :selector=>'//n1:ReturnValue')
      if resp == '4096'
        logger.info("Successfully attached network ISO. Started CIM_ConcreteJob.")
        wait_for_iso_boot(endpoint, logger)
      else
        raise(Error, "Could not attach network ISO. Error code: #{resp}")
      end
    end

    # Checks the status of the iso boot once per minute until the timeout is hit
    def self.wait_for_iso_boot(endpoint, logger=nil, timeout=3600)
      checks = 0
      # Default is to wait up to an hour
      timeout_time = Time.now + timeout
      loop do
        break if Time.now > timeout_time
        checks += 1
        schema = 'http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_OSDConcreteJob?InstanceID=DCIM_OSDConcreteJob:1'
        resp = ''
        status = ''
        message = ''
        begin
          resp = invoke(endpoint, 'get', schema, :logger => logger, :selector => ['//n1:JobStatus', '//n1:Message'] )
          status = resp[0]
          message = resp[1]
          logger.debug("Job status: #{status}") if logger
        rescue ASM::WsMan::Error
          logger.debug("Invalid response...job may not have been initialized yet.  Waiting...") if logger
        end
        if status == 'Success'
          return
        elsif status == 'Failed'
          raise(Error, "Booting from network ISO failed. Error Message: #{message}")
        else
          sleep 60
        end
      end
      raise(Error, "Timed out waiting for ISO to boot")
    end

    # This function will exit when the LC status is 0, or a puppet error will be raised if the LC status never is 0 (never stops being busy)
    def self.wait_for_lc_ready(endpoint, logger = nil, attempts=0, max_attempts=30)
      if(attempts > max_attempts)
        raise(Error, "Life cycle controller is busy")
      else
        status = lcstatus(endpoint, logger).to_i
        if(status == 0)
          return
        else
          logger.debug "LC status is busy: status code #{status}. Waiting..." if logger
          sleep sleep_time
          wait_for_lc_ready(endpoint, logger, attempts+1, max_attempts)
        end
      end
    end

    def self.sleep_time
      60
    end

  end
end
