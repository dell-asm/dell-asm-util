# frozen_string_literal: true

require "asm/wsman"
require "asm/wsman/client"
require "erb"
require "tempfile"
require "asm/transport/racadm"

module ASM
  #  Class for handling server firmware update via WS-Man and RACADM
  class Firmware
    IDRAC_ID = 252_27
    LC_ID = 288_97
    UEFI_DIAGNOSTICS_ID = 258_06
    DRIVER_PACK = 189_81
    OS_COLLECTOR = 101_734

    # Component ids that do not require a reboot (DIRECT UPDATES)
    NO_REBOOT_COMPONENT_IDS = [IDRAC_ID, LC_ID, UEFI_DIAGNOSTICS_ID, DRIVER_PACK, OS_COLLECTOR].freeze

    # Max time to wait for a job to complete
    MAX_WAIT_SECONDS = 3600
    attr_reader :logger

    def initialize(cred, options={})
      @endpoint = cred
      @logger = options[:logger]
    end

    # Used to update server firmware via iDrac
    #
    # @param config [Hash] schema of resources used to update the firmware
    # @example
    #        {"asm::server_update"=>
    #          {"rackserver-5xclw12"=>
    #            {"asm_hostname" =>"172.25.5.100",
    #             "force_restart" => false,
    #             "install_type" => "uri",
    #             "path" => "/var/nfs/firmware/ff8080815746abab0157481ecea1000f/ASMCatalog.xml",
    #             "server_firmware" => "[{\"instance_id\":\"DCIM:INSTALLED#701__NIC.Embedded.1-1-1\",
    #                                     \"uri_path\":\"/var/nfs/firmware/ff8080815746abab0157481ecea1000f/FOLDER03287319M/3/Network_Firmware_0MT4K_WN64_7.10.64.EXE\"
    #                                   }]"
    #            }
    #          }
    #        }
    # @param resource_hash [Array<Hash>] of instances with nfs and uri paths
    # @example
    #      [{"instance_id" => "DCIM:INSTALLED#701__NIC.Embedded.1-1-1",
    #        "uri_path" => "nfs://172.25.5.100/FOLDER03287319M/3/Network_Firmware_0MT4K_WN64_7.10.64.EXE;mountpoint=/var/nfs/firmware/ff808081578bd88601578d525d4e004e"
    #       },
    #       {"instance_id" => "DCIM:INSTALLED#iDRAC.Embedded.1-1#IDRACinfo",
    #        "component_id" => "25227",
    #        "uri_path" => "nfs://172.25.5.100/FOLDER03526343M/2/iDRAC-with-Lifecycle-Controller_Firmware_JHF76_WN64_2.30.30.30_A00.EXE;
    #                       mountpoint="/var/nfs/firmware/ff808081578bd88601578d525d4e004e"
    #       }]
    # @param device_config [Hash]
    # @example
    #      {"cert_name"=>"rackserver-5xclw12",
    #       "host"=>"172.17.5.35",
    #       "port"=>nil,
    #       "path"=>"/asm/bin/idrac-discovery.rb",
    #       "scheme"=>"script",
    #       "arguments"=>{"credential_id"=>"ff80808157bfd05a0157bfd13392000d"},
    #       "user"=>"username",
    #       "enc_password"=>nil,
    #       "password"=> "1234"
    #      }
    #
    # @param logger [Logger]
    # @return [void]
    # @raise [Error] resource_hash was empty
    def self.idrac_fw_install_from_uri(config, resource_hash, device_config, logger)
      raise("Received empty resources to update the firmware on server") if resource_hash.nil?

      cert_name = config["asm::server_update"].keys.first
      options = {:host => device_config["host"], :user => device_config["user"], :password => device_config["password"]}
      firmware_instance = ASM::Firmware.new(options, :logger => logger)
      wsman_instance = ASM::WsMan.new(options, :logger => logger)

      ASM::Util.block_and_retry_until_ready(MAX_WAIT_SECONDS, [ASM::WsMan::RetryException, ASM::WsMan::Error, ASM::WsMan::ResponseError], 60) do
        wsman_instance.poll_for_lc_ready
      end

      firmware_instance.clear_job_queue_retry(wsman_instance)
      force_restart = config["asm::server_update"][cert_name]["force_restart"]
      logger.debug("Idrac FW update, force restart selected for %s" % cert_name) if force_restart
      pre = []
      main = []

      resource_hash.each do |firmware|
        logger.debug(firmware)
        if [LC_ID, IDRAC_ID].include? firmware["component_id"].to_i
          pre << firmware
        else
          main << firmware
        end
      end

      unless pre.empty?
        logger.debug("LC Update required, installing first")
        firmware_instance.update_idrac_firmware(pre, force_restart, wsman_instance)
        ASM::Util.block_and_retry_until_ready(MAX_WAIT_SECONDS, [ASM::WsMan::RetryException, ASM::WsMan::Error, ASM::WsMan::ResponseError], 60) do
          wsman_instance.poll_for_lc_ready
        end
      end
      firmware_instance.update_idrac_firmware(main, force_restart, wsman_instance)

      # After updating Ensure LC is up and in good state before exiting
      ASM::Util.block_and_retry_until_ready(MAX_WAIT_SECONDS, [ASM::WsMan::RetryException, ASM::WsMan::Error, ASM::WsMan::ResponseError], 60) do
        wsman_instance.poll_for_lc_ready # Make sure Lc status was ready
      end
    end

    # Clearing the job_queue with retry
    #
    # make sure lc ready after clearing the job queue other wise reset the IDRAC
    # @param wsman [Object]
    # @return [void]
    # @raise [StandardError] if the command delete_job_queue operation or lc_status was not ready after job queue deletion
    def clear_job_queue_retry(wsman)
      attempts ||= 0
      begin
        attempts += 1

        logger.debug("Waiting for LC ready prior to clearing job queue...")
        ASM::Util.block_and_retry_until_ready(MAX_WAIT_SECONDS, [ASM::WsMan::RetryException, ASM::WsMan::Error, ASM::WsMan::ResponseError], 60) do
          wsman.poll_for_lc_ready
        end

        logger.debug("Clearing the Job Queue...")
        clear_job_id = attempts > 1 ?  "JID_CLEARALL_FORCE" : "JID_CLEARALL"
        resp = wsman.delete_job_queue(:job_id => clear_job_id)

        logger.debug("Sleeping 30 seconds after deleting job queue before polling LC ready...")
        sleep 30

        logger.debug("Waiting for LC ready after clearing job queue...")
        ASM::Util.block_and_retry_until_ready(MAX_WAIT_SECONDS, [ASM::WsMan::RetryException, ASM::WsMan::Error, ASM::WsMan::ResponseError], 60) do
          wsman.poll_for_lc_ready
        end

        if resp[:return_value] == "0"
          logger.debug("Request to clear jobs from the queue was requested successfully...")
          raise("The job queue has not been cleared") unless job_queue_clear?(wsman)
        else
          raise("Unable to clear all the job queue")
        end
      rescue
        logger.debug("Job queue cannot be cleared.") if attempts > 1
        logger.debug("Job queue still shows jobs exist after attempting to clear the job queue.")
        logger.debug("Caught exception in clearing job queue %s: %s" % [$!.class, $!.to_s])
        logger.debug("Resetting the Idrac ...")

        # Resets two times
        if attempts < 3
          transport = ASM::Transport::Racadm.new(wsman.client.endpoint, logger)
          transport.reset_idrac
          sleep 180
          retry
        else
          raise("Unable to find the LC status after clearing job queue")
        end
      end
    end

    def job_queue_clear?(wsman)
      logger.debug("Waiting for job queue to be empty...")
      result = false
      schema = "http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_JobService"
      resp = wsman.client.enumerate(schema)
      num_current_jobs = "NA"

      num_current_jobs_arr = resp.map {|x| x[:current_number_of_jobs]}
      num_current_jobs = num_current_jobs_arr.first if num_current_jobs_arr
      logger.debug("Current number of jobs in the queue = %s" % num_current_jobs)

      if num_current_jobs == "0"
        logger.info("Job Queue is empty.")
        result = true
      end

      result
    end

    # Used to update the iDrac firmware
    #
    # @param firmware_list [Array[<Hash>]] Each instance with mount and nfs path
    # @param force_restart [Boolean]
    # @param wsman [Object]
    # @return [void]
    # @raise [StandardError] if firmware gets_install_uri_job was not able to create job_id to receive or created duplicate job_ids or firmware update fails
    def update_idrac_firmware(firmware_list, force_restart, wsman)
      statuses = []

      # Initiate all firmware update jobs
      firmware_list.each do |fw|
        logger.debug(fw)
        job_id = gets_install_uri_job(fw, wsman)
        raise("Failed to initiate the firmware job for %s" % fw) unless job_id

        statuses << block_until_downloaded(job_id, fw, wsman)
      end

      logger.debug("First statuses set: %s" % statuses.to_s)

      statuses.each do |status|
        if NO_REBOOT_COMPONENT_IDS.include?(status[:firmware]["component_id"].to_i)
          status[:desired] = "Completed"
          status[:reboot_required] = false
        else
          force_restart ? status[:desired] = "Completed" : status[:desired] = "Scheduled"
          status[:reboot_required] = true
        end
      end

      logger.debug("Updated statuses set: %s" % statuses.to_s)

      reboot_firmwares = statuses.select { |status| status[:reboot_required] }
      logger.debug("Reboot firmwares: %s" % reboot_firmwares.to_s)
      completed_endstate_firmwares = statuses.select { |status| status[:desired] == "Completed" }
      scheduled_endstate_firmwares = statuses.select { |status| status[:desired] == "Scheduled" }

      schedule_reboot_job_queue(reboot_firmwares, force_restart, wsman) # Reboot required if firmware instance does not include :component_id key

      [scheduled_endstate_firmwares, completed_endstate_firmwares].each do |firmware_set|
        until firmware_set.all? { |v| v[:status] =~ /#{v[:desired]}|Failed|InternalTimeout/ }
          firmware_set.each do |firmware|
            if firmware[:status] != firmware[:desired] && Time.now - firmware[:start_time] > MAX_WAIT_SECONDS
              firmware[:status] = "InternalTimeout"
            else
              lc_job = wsman.get_lc_job(firmware[:job_id])
              firmware[:status] = lc_job[:job_status]
              logger.debug("Job Status %s: %s" % [firmware[:job_id], firmware[:status]])
            end
          end
          sleep 30
        end
      end
      # Raise an error if any firmware jobs failed
      failures = statuses.find_all { |v| v[:status] =~ /Failed|InternalTimeout/ }
      if failures.empty?
        logger.debug("Firmware update completed successfully")
      else
        logger.info("Failed firmware jobs: #{failures}")
        raise("Firmware update failed in the lifecycle controller. Please refer to LifeCycle job logs")
      end
    end

    # Used to install specified firmware instance on IDRAC
    #
    # @param firmware [Hash]
    # @param wsman [Object]
    # @option firmware [String] :instance_id specifies the particular firmware instance ID
    # @option firmware [String] :uri_path specifies NFS mount share path
    # @option firmware [String] :component_id specifies the component_id for iDRAC
    # @return [String] created JOB_ID
    # @raise [ASM::Error] if install_from_uri wsman command fails or unable to mount the specified firmware path
    def gets_install_uri_job(firmware, wsman)
      config_file = create_xml_config_file(firmware["instance_id"], firmware["uri_path"])
      resp = wsman.install_from_uri(:input_file => config_file.path)

      if resp[:return_value] == "4096"
        job_id = resp[:job]
        logger.debug("InstallFromURI started")
        logger.debug("JOB_ID: #{job_id}")
      else
        logger.debug("Error installing From URI config: %s" % File.read(config_file.path))
        raise("Problem running InstallFromURI: #{resp[:message]}")
      end

      job_id
    end

    # Helper method used to block till firmware status completed
    #
    # @param job_id [String]
    # @param firmware [Hash]
    # @param wsman [Object]
    # @option firmware [String] :instance_id defines each firmware instance ID
    # @option firmware [String] :uri_path defines specific mount share path
    # @option firmware [String] :component_id by default component id is "25227"
    # @return statuses [Hash]
    # @option statuses [String] :job_id created job_id
    # @option statuses ["new", "Failed", "TemporaryFailure", "Downloaded", "Completed"] :status statuses
    # @option statuses [String] :firmware defines specific firmware instance
    # @raise [StandardError]  if the checkjobstatus command fails
    # @raise [Error] if the firmware job status was failed
    def block_until_downloaded(job_id, firmware, wsman)
      status = {
        :job_id => job_id,
        :status => "new",
        :firmware => firmware,
        :start_time => Time.now
      }
      until status[:status] =~ /Downloaded|Completed|Failed/
        sleep 30
        begin
          lc_status = wsman.get_lc_job(job_id)
          status[:status] = lc_status[:job_status]
        rescue
          status[:status] = "TemporaryFailure"
          logger.warn("Look up job status %s failed: %s" % [job_id, $!.to_s])
        end
        logger.debug("Job Status: #{status[:status]}")

        if Time.now - status[:start_time] > MAX_WAIT_SECONDS
          logger.warn("Timed out waiting for firmware job #{job_id} to complete")
          status[:status] = "Failed"
        end
      end

      if status[:status] == "Completed"
        logger.debug("Firmware update completed successfully")
      elsif status[:status] == "Failed"
        raise("Firmware update failed in the lifecycle controller.  Please refer to LifeCycle job logs")
      elsif status[:status] == "Downloaded"
        logger.debug("Firmware downloaded to idrac")
      end
      status
    end

    # Used to schedule the reboot job queue
    #
    # @param reboot_firmwares [Hash] contains list of firmwares which requires reboot
    # @option reboot_firmwares [String] :instance_id contains job_id
    # @option reboot_firmwares [String] :uri_path contains NFS mount path
    # @param force_restart [Boolean]
    # @param wsman [Object]
    # @return [void]
    def schedule_reboot_job_queue(reboot_firmwares, force_restart, wsman)
      unless reboot_firmwares.empty?
        reboot_job_id = nil
        if force_restart
          logger.debug("Creating Reboot Job")
          resp = wsman.create_reboot_job(:reboot_job_type => :power_cycle, :timeout => 5 * 60)
          reboot_job_id = resp[:reboot_job_id]
          logger.debug("Reboot Job scheduled successfully")
        end
        logger.debug("Setting the Job queue")

        job_ids = reboot_firmwares.map {|r| r[:job_id]}

        job_queue_config_file = create_job_queue_config(job_ids, reboot_job_id)
        logger.debug("Job Queue config file: %s" % File.read(job_queue_config_file.path))

        setup_job_queue(job_queue_config_file, wsman)

        if force_restart
          reboot_status = "new"
          until reboot_status == "Reboot Completed"
            sleep 30
            lc_job = wsman.get_lc_job(reboot_job_id)
            reboot_status = lc_job[:job_status]
            logger.debug("Reboot Status: #{reboot_status}")
          end
        end
      end
    end

    # Helper method for seting up firmware job queue
    #
    # There can be intermittent issues caused by the idrac lifecyle controller
    # that causes this to incorrectly fail. This just adds some retry logic around it
    #
    # @param [File] config_file the wsman configuration file to use for the job queue
    # @param [ASM::WsMan] wsman the wsman object
    def setup_job_queue(config_file, wsman)
      logger.debug("Setting up Job Queue")
      4.times do |t|
        resp = wsman.setup_job_queue(:input_file => config_file.path)
        if resp[:return_value] == "0"
          logger.debug("Job Queue created successfully")
          break
        elsif t < 3
          logger.debug("Error scheduling Job Queue.  ..retrying")
          sleep 10
        else
          logger.debug("Error Job Queue config: %s" % File.read(config_file.path))
          raise("Problem scheduling the job queue.  Message: %s" % resp[:message])
        end
      end
    end

    # Creates SetupJobQueue config file
    #
    # this creates a temporary file to be used for the SetupJobQueue wsman call
    #
    # @param job_ids [Array<String>] job ids to be scheduled
    # @param reboot_id [String] the reboot job
    # @return [Tempfile] the xml file object
    def create_job_queue_config(job_ids, reboot_id=nil)
      template = <<~XML
        <p:SetupJobQueue_INPUT xmlns:p="http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_JobService"><% job_ids.each do |job_id| %>
        <p:JobArray><%= job_id %></p:JobArray><% end %><% if reboot_id %>
        <p:JobArray><%= reboot_id %></p:JobArray><% end %>
        <p:RunMonth>6</p:RunMonth>
          <p:RunDay>18</p:RunDay>
        <p:StartTimeInterval>TIME_NOW</p:StartTimeInterval>
        </p:SetupJobQueue_INPUT>
      XML

      xmlout = ERB.new(template)
      temp_file = Tempfile.new("jq_config")
      temp_file.write(xmlout.result(binding))
      temp_file.close
      temp_file
    end

    # Used to create an XML file:
    #
    # @param instance_id [String] job_id
    # @param path [String] specifies moount path
    # @return [Tempfile]
    def create_xml_config_file(instance_id, path)
      template = <<~XML
        <p:InstallFromURI_INPUT xmlns:p="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_SoftwareInstallationService">
        <p:URI><%= path %></p:URI>
        <p:Target xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:w="http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd">
        <a:Address>http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</a:Address>
        <a:ReferenceParameters>
        <w:ResourceURI>http://schemas.dell.com/wbem/wscim/1/cim-schema/2/DCIM_SoftwareIdentity</w:ResourceURI>
        <w:SelectorSet>
        <w:Selector Name="InstanceID"><%= instance_id %></w:Selector>
        </w:SelectorSet> </a:ReferenceParameters> </p:Target> </p:InstallFromURI_INPUT>
      XML

      xmlout = ERB.new(template)
      temp_file = Tempfile.new("xml_config")
      temp_file.write(xmlout.result(binding))
      temp_file.close
      temp_file
    end
  end
end
