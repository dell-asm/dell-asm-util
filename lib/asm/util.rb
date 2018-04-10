require "io/wait"
require "hashie"
require "json"
require "open3"
require "socket"
require "timeout"
require "uri"
require "yaml"
require "time"
require "resolv"

module ASM
  # Use this instead of Thread.new, or your exceptions will disappear into the ether...
  def self.execute_async(logger, &block)
    Thread.new do
      begin
        yield
      # NOTE: really do want to rescue Exception and not StandardError here,
      # otherwise these failures will not be logged anywhere.
      rescue Exception => e # rubocop:disable Lint/RescueException
        logger.error(e.message + "\n" + e.backtrace.join("\n"))
      end
    end
  end

  module Util
    # TODO: give razor user access to this directory
    PUPPET_CONF_DIR = "/etc/puppetlabs/puppet".freeze
    DEVICE_CONF_DIR = "#{PUPPET_CONF_DIR}/devices".freeze
    NODE_DATA_DIR = "#{PUPPET_CONF_DIR}/node_data".freeze
    DEVICE_SSL_DIR = "/var/opt/lib/pe-puppet/devices".freeze
    DATABASE_CONF = "#{PUPPET_CONF_DIR}/database.yaml".freeze
    DEVICE_MODULE_PATH = "/etc/puppetlabs/puppet/modules".freeze
    INSTALLER_OPTS_DIR = "/opt/razor-server/tasks/".freeze
    DEVICE_LOG_PATH = "/opt/Dell/ASM/device".freeze

    # Extract a server serial number from the certname.
    # For Dell servers, the serial number will be the service tag
    # For others, this is hopefully correct but probably not in the long run.
    def self.cert2serial(cert_name)
      /^[^-]+-(.*)$/.match(cert_name)[1].upcase
    end

    # Check to see if this cert is talking about a Dell server.
    # This is arguably laughably wrong, but cannot be fixed here for now for
    # hysterical reasons.  As an additional guard, the serial number portion
    # of the cert name must be exactly 7 chars in length for it to be
    # considered a Dell service tag.
    def self.dell_cert?(cert_name)
      cert_name =~ /^(blade|rack|fx|tower)server-.{7}$/
    end

    def self.is_ip_address_accessible(ip_address)
      system("ping -c 1 -w 1 %s" % ip_address)
    end

    # Hack to figure out cert name from uuid.
    #
    # For UUID 4223-c288-0e73-104e-e6c0-31f5f65ad063
    # Shows up in puppet as VMware-42 23 c2 88 0 e 73 10 4 e-e6 c0 31 f5 f6 5 a d0 63
    def self.vm_uuid_to_serial_number(uuid)
      without_dashes = uuid.delete("-")
      raise("Invalid uuid #{uuid}") unless without_dashes.length == 32
      first_half = []
      last_half = []
      (0..7).each do |i|
        start = i * 2
        first_half.push(without_dashes[start..start + 1])
        start = i * 2 + 16
        last_half.push(without_dashes[start..start + 1])
      end
      "VMware-#{first_half.join(' ')}-#{last_half.join(' ')}"
    end

    def self.rescan_vmware_esxi(esx_endpoint, logger)
      cmd = "storage core adapter rescan --all".split
      ASM::Util.esxcli(cmd, esx_endpoint, logger, true, 1200)
    end

    def self.first_host_ip
      Socket.ip_address_list.detect do |intf|
        intf.ipv4? && !intf.ipv4_loopback? && !intf.ipv4_multicast?
      end.ip_address
    end

    # Return the host IP that routes to the specified host
    #
    # Uses `ip route get` to determine which local interface traffic to the
    # specified remote host will be routed through. The IP address of that
    # local interface is returned. The remote host should be able to access
    # the local host via that IP.
    #
    # @param [String] remote_host Remote host to access
    #
    # @return [String] the local host IP address
    def self.get_preferred_ip(remote_host, logger=nil)
      tries = 0
      max_tries = 10
      preferred = nil

      ip = Resolv.getaddress(remote_host)

      while tries < max_tries
        parts = `ip route get #{ip}`.split(/\s+/)

        if position = parts.index("src")
          preferred = parts[position + 1]
          break
        else
          message = "failed to determine target route from routing table: \n%s" % `ip route`

          puts(message) unless logger
          logger.debug(message) if logger

          sleep 1
        end

        tries += 1
      end

      if tries == max_tries
        address = ip == remote_host ? ip : "%s (%s)" % [remote_host, ip]
        raise("Failed to find preferred route to %s after %d tries" % [address, tries])
      end

      preferred
    end

    def self.default_routed_ip
      result = run_command_with_args("ip route show 0/0")
      gateway = result["stdout"].split(/\s+/)[2].match(Resolv::IPv4::Regex).to_s
      get_preferred_ip(gateway)
    end

    # Execute esxcli command and parse table into list of hashes.
    #
    # Example output:
    #
    # esxcli -s 172.25.15.174 -u root -p linux network vswitch standard portgroup list
    # Name                    Virtual Switch  Active Clients  VLAN ID
    # ----------------------  --------------  --------------  -------
    # Management Network      vSwitch0                     1        0
    # vMotion                 vSwitch1                     1       23
    def self.esxcli(cmd_array, endpoint, logger=nil, skip_parsing=false, time_out=600)
      unless cmd_array.empty?
        endpoint[:thumbprint] ||= begin
          thumbprint_output = esxcli([], endpoint, logger, true, time_out)
          thumbprint_output.slice(/(?<=thumbprint: )(.*)(?= \(not)/)
        end
      end
      args = [time_out.to_s, "env", "VI_PASSWORD=#{endpoint[:password]}", "esxcli"]
      args += ["-s", endpoint[:host],
               "-u", endpoint[:user]
      ]
      args += ["-d", endpoint[:thumbprint]] if endpoint[:thumbprint]
      args += cmd_array.map(&:to_s)

      if logger
        tmp = args.dup
        tmp[2] = "VI_PASSWORD=******" # mask password
        logger.debug("Executing esxcli #{tmp.join(' ')}")
      end
      result = ASM::Util.run_command_with_args("timeout", *args)

      if result["exit_status"] != 0 && !cmd_array.empty?
        msg = "Failed to execute esxcli command on host #{endpoint[:host]}"
        logger.error(msg) if logger
        args[2] = "VI_PASSWORD=******" # mask password
        raise("#{msg}: esxcli #{args.join(' ')}: #{result.inspect}")
      end

      if skip_parsing
        result["stdout"]
      else
        parse_esxcli_result(result["stdout"])
      end
    end

    def self.parse_esxcli_result(result_stdout)
      lines = result_stdout.split(/\n/)
      if lines.size >= 2
        header_line = lines.shift
        seps = lines.shift.split
        headers = []
        pos = 0
        seps.each do |sep|
          header = header_line.slice(pos, sep.length).strip
          headers.push(header)
          pos = pos + sep.length + 2
        end

        ret = []
        lines.each do |line|
          record = {}
          pos = 0
          seps.each_with_index do |sep, index|
            value = line.slice(pos, sep.length).strip
            record[headers[index]] = value
            pos = pos + sep.length + 2
          end
          ret.push(record)
        end
        ret
      end
    end

    def self.get_fcoe_adapters(esx_endpoint, logger=nil)
      fcoe_adapters = []
      fcoe_adapter = esxcli("fcoe nic list".split, esx_endpoint, logger, true)
      if fcoe_adapter
        fcoe_adapter_match = fcoe_adapter.scan(/^(vmnic\d+)\s+/m)
        if fcoe_adapter_match
          fcoe_adapter_match.each do |matched|
            fcoe_adapters.push(matched[0])
          end
        end
      end
      fcoe_adapters
    end

    # Execute a command with arguments
    #
    # The command will not be invoked within a shell unless the cmd argument itself is a shell.
    #
    # WARNING: Commands producing a large amount of stderr vs stdout will deadlock as the
    # implementation just consumes all stdout before consuming stderr.
    #
    # @example
    #
    #    [3] pry(main)> ASM::Util.run_command_with_args("echo", "hello", "my", "friend")
    #    => {"stdout"=>"hello my friend\n", "stderr"=>"", "pid"=>9762, "exit_status"=>0}
    #    [4] pry(main)> ASM::Util.run_command_with_args("ls", "/noexist1", "/noexist2")
    #    => {"stdout"=>"",
    #        "stderr"=>
    #          "ls: cannot access '/noexist1': No such file or directory\nls: cannot access '/noexist2': No such file or directory\n",
    #        "pid"=>9842,
    #        "exit_status"=>2}
    #
    # @return [Hashie::Mash] Mash with stdout, stderr, pid and exit_status keys
    def self.run_command_with_args(cmd, *args)
      run_command(cmd, *args)
    end

    # Executes a command with clean environment variables
    # Params:
    # +cmd:   comand line string to be executed
    # +fail_on_error: bool that raises exception if command doesn't return 0 status
    # +args[,env]: command line arguments.  can set env vars with last element as hash

    def self.run_with_clean_env(cmd, fail_on_error, *args)
      env_vars = args.last.is_a?(Hash) ? args.pop : {}
      new_args = []
      %w(BUNDLE_BIN_PATH GEM_PATH RUBYLIB GEM_HOME RUBYOPT).each do |e|
        new_args.insert(0, "--unset=#{e}")
      end
      new_args.push(cmd)
      new_args.push(*args) if args
      if fail_on_error
        run_command_success(env_vars, "/bin/env", *new_args)
      else
        run_command(env_vars, "/bin/env", *new_args)
      end
    end

    def self.run_command_success(cmd, *args)
      result = run_command(cmd, *args)
      raise("Command failed: #{cmd}\n#{result.stdout}\n#{result.stderr}") unless result.exit_status == 0
      result
    end

    def self.run_command(cmd, *args)
      result = Hashie::Mash.new
      Open3.popen3(cmd, *args) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        result.stdout      = stdout.read
        result.stderr      = stderr.read
        result.pid         = wait_thr[:pid]
        result.exit_status = wait_thr.value.exitstatus
      end

      result
    end

    # Run cmd by passing it to the shell and stream stdout and stderr
    # to the specified outfile
    def self.run_command_streaming(cmd, outfile)
      File.open(outfile, "a") do |fh|
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          stdin.close

          files = [stdout, stderr]

          # Attempt to interleave stdout and stderr if possible
          # by using gets instead of read_nonblock to read a
          # line at a time. Slower but interleaves better.
          until files.empty?
            ready = IO.select(files)
            readable = ready[0]
            readable.each do |f|
              begin
                data = f.gets
                if data.nil?
                  # gets returns nil on EOF so remove this file
                  # from the list of files to select on (read from)
                  files.delete(f)
                else
                  fh.write data
                  fh.flush
                end
              rescue IOError
                # A catch-all to prevent spinning in case
                # some weird exception happens - just delete
                # the offending file from the list
                files.delete(f)
              end
            end
          end

          fh.close
          raise("#{cmd} failed; output in #{outfile}") unless wait_thr.value.exitstatus == 0
        end
      end
    end

    def self.block_and_retry_until_ready(timeout, exceptions=nil, max_sleep=nil, logger=nil, &block)
      failures = 0
      sleep_time = 0
      Timeout.timeout(timeout) do
        begin
          yield
        rescue => e

          exceptions = Array(exceptions)
          if !exceptions.empty? && (
            exceptions.include?(key = e.class) ||
            exceptions.include?(key = key.name.to_s) ||
            exceptions.include?(key = key.to_sym)
          )
            logger.info("Caught exception #{e.class}: #{e}") if logger
            failures += 1
            sleep_time = (((2**failures) - 1) * 0.1)
            sleep_time = max_sleep if max_sleep && (sleep_time > max_sleep)
            sleep sleep_time
            retry
          else
            # If the exceptions is not in the list of retry_exceptions re-raise.
            raise e
          end
        end
      end
    end

    # ASM services send single-element arrays as just the single element (hash).
    # This method ensures we get a single-element array in that case
    def self.asm_json_array(elem)
      if elem.is_a?(Hash)
        [elem]
      else
        elem
      end
    end

    def self.to_boolean(b)
      if b.is_a?(String)
        b.downcase == "true"
      else
        b
      end
    end

    def self.sanitize(hash)
      ret = hash.dup
      ret.each do |key, value|
        if value.is_a?(Hash)
          ret[key] = sanitize(value)
        elsif key.to_s.downcase =~ /password|pwd/
          ret[key] = "******"
        end
      end
    end

    def self.hostname_to_certname(hostname)
      "agent-%s" % hostname.downcase.gsub(%r{[*'_/!~`@#%^&()$]}, "")
    end

    def self.load_file(filename, base_dir=INSTALLER_OPTS_DIR)
      filepath = File.join(base_dir, filename)
      result = {}
      if File.exist?(filepath)
        if File.extname(filename) == ".yaml"
          result = YAML.load_file(filepath)
        else
          result = File.read(filepath)
        end
      end
      result
    end

    def self.hyperv_cluster_hostgroup(cert_name, cluster_name)
      conf = ASM::DeviceManagement.parse_device_config(cert_name)
      domain, user = conf["user"].split('\\')
      cmd = File.join(File.dirname(__FILE__), "scvmm_cluster_information.rb")
      args = [cmd, "-u", user, "-d", domain, "-p", conf["password"], "-s", conf["host"], "-c", cluster_name]
      result = ASM::Util.run_with_clean_env("/opt/puppet/bin/ruby", false, *args)
      host_group = "All Hosts"
      result.stdout.split("\n").reject {|l| l.empty? || l == "\r"}.drop(2).each do |line|
        host_group = $1 if line.strip =~ /hostgroup\s*:\s+(.*)?$/i
      end
      host_group
    end

    # Does a deep merge on a hash
    def self.deep_merge!(source, new_hash)
      merger = proc { |_, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.merge(v2, &merger) : v2 }
      source.merge!(new_hash, &merger)
    end
  end
end
