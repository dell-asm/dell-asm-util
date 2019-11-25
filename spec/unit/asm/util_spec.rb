# frozen_string_literal: true

require "asm/util"
require "asm/errors"
require "net/ssh"
require "spec_helper"
require "tempfile"
require "json"

describe ASM::Util do
  before do
    @tmpfile = Tempfile.new("AsmUtil_spec")
  end

  after do
    @tmpfile.unlink
  end

  describe "retries and timeouts" do
    it "should reraise unhandled exceptions" do
      expect do
        ASM::Util.block_and_retry_until_ready(1) do
          raise(ASM::Error)
        end
      end.to raise_error(ASM::Error)
    end

    it "should raise an exception on timeout" do
      expect do
        ASM::Util.block_and_retry_until_ready(1) do
          sleep 2
        end
      end.to raise_error(Timeout::Error)
    end

    it "should forgive a single exception" do
      mock_log = mock("foo")
      mock_log.expects(:info).with("Caught exception ASM::Error: ASM::Error")
      expects(:foo).twice.raises(ASM::Error).then.returns("bar")
      expect(ASM::Util.block_and_retry_until_ready(5, ASM::Error, nil, mock_log) do
        foo
      end).to eq("bar")
    end

    it "should defer to max sleep time" do
      expects(:foo).twice.raises(ASM::Error).then.returns("bar")
      ASM::Util.expects(:sleep).with(0.01)
      expect(ASM::Util.block_and_retry_until_ready(5, ASM::Error, 0.01) do
        foo
      end).to eq("bar")
    end
  end

  describe "when uuid is valid" do
    it "should create the corresponding serial number" do
      uuid = "423b69b2-8bd7-0dde-746b-75c98eb74d2b"
      expect(ASM::Util.vm_uuid_to_serial_number(uuid)).to eq("VMware-42 3b 69 b2 8b d7 0d de-74 6b 75 c9 8e b7 4d 2b")
    end
  end

  describe "when uuid is not valid" do
    it "should raise an exception" do
      uuid = "lkasdjflkasdj"
      expect do
        ASM::Util.vm_uuid_to_serial_number(uuid)
      end.to raise_error("Invalid uuid lkasdjflkasdj")
    end
  end

  it "should parse esxcli thumbprint and output" do
    esxcli_thumbprint_msg = <<~OUTPUT
      Connect to 100.1.1.100 failed. Server SHA-1 thumbprint: 28:C6:8D:54:1B:08:A1:08:7A:0B:50:6D:B7:73:06:96:71:A1:6D:03 (not trusted).
    OUTPUT

    err_result = {
      "exit_status" => 1,
      "stdout" => esxcli_thumbprint_msg
    }

    stdout = <<~OUTPUT
      Name                    Virtual Switch  Active Clients  VLAN ID
      ----------------------  --------------  --------------  -------
      ISCSI0                  vSwitch3                     1       16
      ISCSI1                  vSwitch3                     1       16
      Management Network      vSwitch0                     1        0
      Management Network (1)  vSwitch0                     1       28
      VM Network              vSwitch0                     1        0
      Workload Network        vSwitch2                     0       20
      vMotion                 vSwitch1                     1       23

    OUTPUT

    result = {
      "exit_status" => 0,
      "stdout" => stdout
    }
    ASM::Util.stubs(:run_command_with_args).returns(err_result, result)
    endpoint = {}
    ret = ASM::Util.esxcli(["command_to_get_network_info"], endpoint)
    expect(ret.size).to eq(7)
    expect(ret[3]["Name"]).to eq("Management Network (1)")
    expect(ret[3]["Virtual Switch"]).to eq("vSwitch0")
    expect(ret[3]["Active Clients"]).to eq("1")
    expect(ret[3]["VLAN ID"]).to eq("28")
  end

  it "should parse esxcli output and use provided thumbprint" do
    stdout = <<~OUTPUT
      Name                    Virtual Switch  Active Clients  VLAN ID
      ----------------------  --------------  --------------  -------
      ISCSI0                  vSwitch3                     1       16
      ISCSI1                  vSwitch3                     1       16
      Management Network      vSwitch0                     1        0
      Management Network (1)  vSwitch0                     1       28
      VM Network              vSwitch0                     1        0
      Workload Network        vSwitch2                     0       20
      vMotion                 vSwitch1                     1       23

    OUTPUT

    result = {
      "exit_status" => 0,
      "stdout" => stdout
    }
    ASM::Util.stubs(:run_command_with_args).returns(result)
    endpoint = {:thumbprint => "28:C6:8D:54:1B:08:A1:08:7A:0B:50:6D:B7:73:06:96:71:A1:6D:03"}
    ret = ASM::Util.esxcli([], endpoint)
    expect(ret.size).to eq(7)
    expect(ret[3]["Name"]).to eq("Management Network (1)")
    expect(ret[3]["Virtual Switch"]).to eq("vSwitch0")
    expect(ret[3]["Active Clients"]).to eq("1")
    expect(ret[3]["VLAN ID"]).to eq("28")
  end

  it "should fail if thumbprint not found" do
    result = {"exit_status" => 2, "stdout" => "Bang!"}
    ASM::Util.stubs(:run_command_with_args).returns(result)
    expect { ASM::Util.esxcli(%w[system uuid get], :host => "rspec-host") }.to raise_error("Thumbprint retrieval failed for host rspec-host: Bang!")
  end

  describe "when hash is deep" do
    it "should sanitize password value" do
      raw = {"foo" => {"password" => "secret"}}
      expect(ASM::Util.sanitize(raw)).to eq("foo" => {"password" => "******"})
    end

    it "should maintain password value" do
      raw = {"foo" => {"password" => "secret"}}
      ASM::Util.sanitize(raw)
      expect(raw).to eq("foo" => {"password" => "secret"})
    end
  end

  describe "#hostname_to_certname" do
    it "should generate a certname and not clobber the original hostname" do
      certname = "CrAzY_NaMe1234"
      expect(ASM::Util.hostname_to_certname(certname)).to eq("agent-crazyname1234")
      expect(certname).to eq("CrAzY_NaMe1234")
    end
  end

  describe "#deep_merge!" do
    it "should recursively merge one hash into another" do
      original = {"asm::fcdatastore" =>
                    {"drsmixh01:drs-cplmix03" =>
                       {"data_center" => "drsmix01dc", "datastore" => "drs-cplmix03",
                        "cluster" => "drsmix01dc", "ensure" => "present",
                        "esxhost" => "172.31.37.143", "lun" => nil, "iscsi_volume" => true}}}
      new = {"asm::fcdatastore" =>
               {"drsmixh01:drs-cplmix04" =>
                  {"data_center" => "drsmix01dc", "datastore" => "drs-cplmix04", "cluster" => "drsmix01dc",
                   "ensure" => "present", "esxhost" => "172.31.37.143", "lun" => nil, "iscsi_volume" => true}}}
      ASM::Util.deep_merge!(original, new)
      expect(original).to eq("asm::fcdatastore" =>
                                {"drsmixh01:drs-cplmix03" =>
                                   {"data_center" => "drsmix01dc", "datastore" => "drs-cplmix03", "cluster" => "drsmix01dc",
                                    "ensure" => "present", "esxhost" => "172.31.37.143", "lun" => nil, "iscsi_volume" => true},
                                 "drsmixh01:drs-cplmix04" =>
                                   {"data_center" => "drsmix01dc", "datastore" => "drs-cplmix04", "cluster" => "drsmix01dc",
                                    "ensure" => "present", "esxhost" => "172.31.37.143", "lun" => nil, "iscsi_volume" => true}})
    end
  end

  describe "#get_preferred_ip" do
    let(:logger) { Logger.new(nil) }

    it "should find the host ip" do
      Resolv.expects(:getaddress).with("host-foo").returns("192.168.253.100")

      ASM::Util.expects(:`)
               .with("ip route get 192.168.253.100")
               .returns(<<~OUTPUT
                 192.168.253.100 dev ens192 src 192.168.253.1
                     cache

               OUTPUT
                       )

      expect(ASM::Util.get_preferred_ip("host-foo", logger)).to eq("192.168.253.1")
    end

    it "should retry a few times and fail" do
      Resolv.expects(:getaddress).with("192.168.253.100").returns("192.168.253.100")

      ASM::Util.expects(:sleep).at_least_once
      ASM::Util.expects(:`).at_least_once.with("ip route get 192.168.253.100").returns("Error")

      ASM::Util.expects(:`)
               .at_least_once
               .with("ip route")
               .returns(<<~OUTPUT
                 default via 100.68.107.190 dev ens160 proto static metric 100
                 100.68.107.128/26 dev ens160 proto kernel scope link src 100.68.107.160 metric 100
                 192.168.253.0/24 dev ens192 proto kernel scope link src 192.168.253.1 metric 100

               OUTPUT
                       )

      expect {ASM::Util.get_preferred_ip("192.168.253.100", logger)}.to raise_error("Failed to find preferred route to 192.168.253.100 after 10 tries")
    end
  end

  describe "#run_command_streaming" do
    it "should not block for stderr only case" do
      outfile = Tempfile.new("run_command_streaming")
      command = SpecHelper::FIXTURE_PATH + "/print_to_fd.sh"
      ASM::Util.run_command_streaming(command + " 2 20 'Hi there'", outfile)
      expected_output = SpecHelper::FIXTURE_PATH + "/util/stderr_only_short.out"
      expect(File.readlines(outfile).sort).to eq(File.readlines(expected_output.to_s).sort)
      outfile.unlink
    end

    it "should not block for stdout only case" do
      outfile = Tempfile.new("run_command_streaming")
      command = SpecHelper::FIXTURE_PATH + "/print_to_fd.sh"
      ASM::Util.run_command_streaming(command + " 1 20 'Hi there'", outfile)
      expected_output = SpecHelper::FIXTURE_PATH + "/util/stdout_only_short.out"
      expect(File.readlines(outfile).sort).to eq(File.readlines(expected_output.to_s).sort)
      outfile.unlink
    end

    it "should not block for stdout and stderr case" do
      outfile = Tempfile.new("run_command_streaming")
      command = SpecHelper::FIXTURE_PATH + "/print_to_fd.sh"
      ASM::Util.run_command_streaming(command + " 3 20 'Hi there'", outfile)
      expected_output = SpecHelper::FIXTURE_PATH + "/util/stdout_stderr_short.out"
      expect(File.readlines(outfile).sort).to match_array(File.readlines(expected_output.to_s).sort)
      outfile.unlink
    end
  end

  describe "#write_ansible_yaml" do
    it "should write a provided hash to file location" do
      outfile = Tempfile.new("ansible_out.yaml")
      yaml_hash = {"rhvm" =>
                       {"hosts" =>
                            {"100.68.106.94" =>
                                 {"ansible_ssh_pass" => "!vault |\n         " \
                                              "$ANSIBLE_VAULT;1.1;AES256\n          " \
                                              "63646239656565393165663132303561656331313063643235383736633732343530666539343034\n" \
                                              "          6638393531323732663937363731653766623264333034370a343435316265636631646463303931\n" \
                                              "          33623562623537623964353464356435393537306338306430343466643230313436316639393835\n" \
                                              "          3136633862343232650a623931393335623034356138333362646331303864656366323062313630\n" \
                                              "          6562\n"}},
                        "vars" =>
                            {"rhn_satellite" => "https://rsatnew.asm.delllabs.net",
                             "katello_rpm" => "katello-ca-consumer-latest.noarch.rpm",
                             "rhn_org" => "dellemc",
                             "rhv_key" => "RHV",
                             "rhvurl" => "http://arhvm.asm.delllabs.net"}}}
      ASM::Util.write_ansible_yaml(yaml_hash, outfile)
      expected_output = File.join(SpecHelper::FIXTURE_PATH + "/write_ansible.yaml")
      expect(File.readlines(outfile)).to match_array(File.readlines(expected_output))
    end
  end

  describe "#encyrpt_string_with_vault" do
    it "should return a vault encrypted string" do
      expected_out = "!vault |\n          " \
                     "$ANSIBLE_VAULT;1.1;AES256\n     " \
                     "32636662643664376338336239356435393462343761613064326432663066313662316637316265\n"\
                     "          3366646564386236373833333562393538396462353730300a646337643036393435343830653431\n" \
                     "          30346563343364396333343436636562613261373962613163616235613631666131636333643161\n" \
                     "          3734666238313330300a323563626330373235373035616633396234383962623939663236313832\n" \
                     "          3061\n"
      input = mock("input")
      input.stubs(:write)
      input.stubs(:close)
      output = mock("output")
      output.stubs(:read).returns(expected_out)
      err = mock("err")
      err.stubs(:read)
      val = mock("value")
      val.stubs(:exitstatus).returns(0)
      wait_thru = mock(:[] => 101)
      wait_thru.stubs(:value).returns(val)
      Open3.expects(:popen3).yields(input, output, err, wait_thru).returns("stdout" => expected_out, "exit_status" => 0)
      expect(ASM::Util.encrypt_string_with_vault("ff808081656d80c701656d80d8e40003", "P@ssw0rd", "/opt/dell/asm-deployer/scripts/vault.py")).to eq(expected_out)
    end

    it "should raise error if command fails" do
      expected_out = "error"
      input = mock("input")
      input.stubs(:write)
      input.stubs(:close)
      output = mock("output")
      output.stubs(:read).returns(expected_out)
      err = mock("err")
      err.stubs(:read)
      val = mock("value")
      val.stubs(:exitstatus).returns(1)
      wait_thru = mock(:[] => 101)
      wait_thru.stubs(:value).returns(val)
      Open3.expects(:popen3).yields(input, output, err, wait_thru)
      expect {ASM::Util.encrypt_string_with_vault("ff808081656d80c701656d80d8e40003", "P@ssw0rd", "/opt/dell/asm-deployer/scripts/vault.py")}
        .to raise_error("Error getting vault value: ")
    end

    it "should raise error if no vault password id provided" do
      expect {ASM::Util.encrypt_string_with_vault(nil, "P@ssw0rd", "/opt/dell/asm-deployer/scripts/vault.py")}
        .to raise_error("Error vault password id required")
    end

    it "should raise error if no vault password file provided" do
      expect {ASM::Util.encrypt_string_with_vault("ff808081656d80c701656d80d8e40003", "P@ssw0rd", nil)}
        .to raise_error("Error vault password file required")
    end

    it "should raise error if no value to encrypt provided" do
      expect {ASM::Util.encrypt_string_with_vault("ff808081656d80c701656d80d8e40003", nil, "/opt/dell/asm-deployer/scripts/vault.py")}
        .to raise_error("Error no value to encrypt provided")
    end
  end

  describe "parse ansible log" do
    it "should return json result of run" do
      output_location = File.join(SpecHelper::FIXTURE_PATH + "/testdevice.out")
      expected_out = {"stats" =>
                          {"100.68.106.92" =>
                               {"changed" => 4,
                                "failures" => 0,
                                "ok" => 8,
                                "skipped" => 0,
                                "unreachable" => 0},
                           "100.68.106.93" =>
                               {"changed" => 4,
                                "failures" => 0,
                                "ok" => 8,
                                "skipped" => 0,
                                "unreachable" => 0},
                           "100.68.106.94" =>
                               {"changed" => 4,
                                "failures" => 0,
                                "ok" => 8,
                                "skipped" => 0,
                                "unreachable" => 0}}}
      expect(ASM::Util.parse_ansible_log(output_location)).to eq(expected_out)
    end

    it "should return json result of run even if there is a failure" do
      output_location = File.join(SpecHelper::FIXTURE_PATH + "/testdevice2.out")
      expected_out = {"stats" =>
                          {"100.68.106.96" =>
                               {"changed" => 0,
                                "failures" => 1,
                                "ok" => 0,
                                "skipped" => 0,
                                "unreachable" => 0}}}
      expect(ASM::Util.parse_ansible_log(output_location)).to eq(expected_out)
    end
  end

  describe "#remove_host_entries" do
    it "should remove ips from host file if present" do
      args = %w[ssh-keygen -R 100.68.106.193]
      ASM::Util.expects(:run_command).with(*args).returns("exit_status" => 0)
      args = %w[ssh-keygen -R 100.68.106.196]
      ASM::Util.expects(:run_command).with(*args).returns("exit_status" => 0)
      expect(ASM::Util.remove_host_entries(["100.68.106.193", "100.68.106.196"])).to eq([])
    end

    it "should return ips that failed to remove" do
      args = %w[ssh-keygen -R 100.68.106.193]
      ASM::Util.expects(:run_command).with(*args).returns("exit_status" => 1)
      args = %w[ssh-keygen -R 100.68.106.196]
      ASM::Util.expects(:run_command).with(*args).returns("exit_status" => 0)
      expect(ASM::Util.remove_host_entries(["100.68.106.193", "100.68.106.196"])).to eq(["100.68.106.193"])
    end
  end

  describe "run_ansible_playbook_with_inventory" do
    before(:each) do
      @play = "/tmp/testplay.yaml"
      @inventory = "/tmp/testinventory.yaml"
      @output_file = "/tmp/output.out"
      @arg1 = "/bin/env"
      @arg2 = "--unset=RUBYOPT"
      @arg3 = "--unset=GEM_HOME"
      @arg4 = "--unset=RUBYLIB"
      @arg5 = "--unset=GEM_PATH"
      @arg6 = "--unset=BUNDLE_BIN_PATH"
      @arg7 = "ansible-playbook"
      @arg8 = "-i"
      @arg9 = "/tmp/testinventory.yaml"
      @arg10 = "/tmp/testplay.yaml"
      @arg11 = "--vault-password-file"
      @arg12 = "/tmp/script.sh"
      @arg13 = "timeout"
      @arg14 = "1800"
      @input = mock("input")
      @input.stubs(:write)
      @input.stubs(:close)
      @output = mock("output")
      @output.stubs(:read).returns("test")
      @err = mock("err")
      @err.stubs(:read)
      @val = mock("value")
      @val.stubs(:exitstatus).returns(0)
      @wait_thru = mock("waitthr")
      @wait_thru.stubs(:[]).returns(101)
      @wait_thru.stubs(:value).returns(@val)
    end

    it "should run ansible with the provided playbook and inventory files without verbose" do
      Open3.stubs(:popen3)
           .with({"ANSIBLE_STDOUT_CALLBACK" => "json",
                  "ANSIBLE_HOST_KEY_CHECKING" => "False",
                  "ANSIBLE_SSH_ARGS" => '"-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"'},
                 @arg1,
                 @arg2,
                 @arg3,
                 @arg4,
                 @arg5,
                 @arg6,
                 @arg13,
                 @arg14,
                 @arg7,
                 @arg8,
                 @arg9,
                 @arg10)
           .yields(@input, @output, @err, @wait_thru)
           .returns(nil)
      expect(ASM::Util.run_ansible_playbook_with_inventory(@play, @inventory, @output_file)).to eq(nil)
    end

    it "should run ansible with the provided playbook and inventory files" do
      Open3.stubs(:popen3)
           .with({"ANSIBLE_STDOUT_CALLBACK" => "json",
                  "ANSIBLE_HOST_KEY_CHECKING" => "False",
                  "ANSIBLE_SSH_ARGS" => '"-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"'},
                 @arg1,
                 @arg2,
                 @arg3,
                 @arg4,
                 @arg5,
                 @arg6,
                 @arg13,
                 @arg14,
                 @arg7,
                 @arg8,
                 @arg9,
                 @arg10)
           .yields(@input, @output, @err, @wait_thru)
           .returns(nil)
      expect(ASM::Util.run_ansible_playbook_with_inventory(@play, @inventory, @output_file)).to eq(nil)
    end

    it "should raise error if no playbook provided" do
      expect {ASM::Util.run_ansible_playbook_with_inventory(nil, @inventory, @output_file)}.to raise_error("No playbook file provided")
    end

    it "should raise error if no inventory provided" do
      expect {ASM::Util.run_ansible_playbook_with_inventory(@play, nil, @output_file)}.to raise_error("No inventory file provided")
    end

    it "should raise error if output file provided" do
      expect {ASM::Util.run_ansible_playbook_with_inventory(@play, @inventory, nil)}.to raise_error("No output file provided")
    end

    it "should raise error if vault password id provided with no vault password file" do
      expect {ASM::Util.run_ansible_playbook_with_inventory(@play, @inventory, @output_file, :vault_password_id => "ff808081656d80c701656d80d8e40003")}
        .to raise_error("Vault password id requires vault password file")
    end

    it "should pass in options as environment variables" do
      Open3.expects(:popen3)
           .with({"VAULT" => "test",
                  "ANSIBLE_STDOUT_CALLBACK" => "json",
                  "ANSIBLE_HOST_KEY_CHECKING" => "False",
                  "ANSIBLE_SSH_ARGS" => '"-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"'},
                 @arg1,
                 @arg2,
                 @arg3,
                 @arg4,
                 @arg5,
                 @arg6,
                 @arg13,
                 @arg14,
                 @arg7,
                 @arg8,
                 @arg9,
                 @arg10,
                 @arg11,
                 @arg12)
           .yields(@input, @output, @err, @wait_thru)
           .returns(nil)
      expect(ASM::Util.run_ansible_playbook_with_inventory(@play,
                                                           @inventory,
                                                           @output_file,
                                                           :vault_password_id => "test",
                                                           :stdout_callback => "json",
                                                           :vault_password_file => "/tmp/script.sh")).to eq(nil)
    end
  end

  describe "#execute_script_via_ssh" do
    it "it should run ssh command" do
      session = mock("session")
      channel = mock("channel")
      channel.expects(:exec).yields("test", true)
      channel.expects(:on_data).yields(nil, "test")
      channel.expects(:on_extended_data)
      channel.expects(:on_request)
      session.expects(:open_channel).at_least_once.yields(channel)
      session.expects(:loop)
      Net::SSH.expects(:start)
              .with("155.68.106.198", "root", :password => "P@ssw0rd", :verify_host_key => false, :global_known_hosts_file => "/dev/null")
              .yields(session)
      result = ASM::Util.execute_script_via_ssh("155.68.106.198", "root", "P@ssw0rd", "ls", "-lrt")
      expect(result).to eq(:exit_code => -1, :stderr => "", :stdout => "test")
    end
  end

  describe "#parse_table" do
    it "should return an empty array for empty data" do
      expect(ASM::Util.parse_table("")).to eq([])
    end

    it "should parse ftos lldp neighbors" do
      table = <<-LLDP_NEIGHBORS
 Loc PortID     Rem Host Name     Rem Port Id                        Rem Chassis Id
 --------------------------------------------------------------------------------

 Te 1/1         -                 24:8a:07:b9:d8:10                  24:8a:07:b9:d8:10
 Te 1/2         -                 24:8a:07:b9:d8:11                  24:8a:07:b9:d8:11
 Te 1/3         localhost.local...e4:1d:2d:bf:d7:e0                  e4:1d:2d:bf:d7:e0
 Te 1/4         localhost.local...e4:1d:2d:bf:d7:e1                  e4:1d:2d:bf:d7:e1
 Te 1/5         localhost.local...24:8a:07:5b:e7:90                  24:8a:07:5b:e7:90
 Te 1/6         localhost.local...24:8a:07:5b:e7:91                  24:8a:07:5b:e7:91
 Te 1/7         localhost.local...e4:1d:2d:bf:d6:a0                  e4:1d:2d:bf:d6:a0
 Te 1/9         localhost.local...e4:1d:2d:bf:d6:a1                  e4:1d:2d:bf:d6:a1
 Te 1/17        -                 e4:43:4b:12:98:88                  e4:43:4b:12:98:88
 Te 1/18        -                 e4:43:4b:12:91:c0                  e4:43:4b:12:91:c0
 Te 1/19        -                 00:0a:f7:14:fd:f0                  00:0a:f7:14:fd:f0
 Te 1/20        -                 e4:43:4b:12:d0:aa                  e4:43:4b:12:d0:aa
 Te 1/21        -                 e4:43:4b:12:92:8c                  e4:43:4b:12:92:8c
 Te 1/27        -                 d0:43:1e:a1:d7:01                  d0:43:1e:a1:d7:01
 Te 1/28        -                 d0:43:1e:a1:d7:ef                  d0:43:1e:a1:d7:ef
 Te 1/29        -                 d0:43:1e:a1:d7:69                  d0:43:1e:a1:d7:69
 Te 1/31        -                 d0:43:1e:a1:d7:1b                  d0:43:1e:a1:d7:1b
 Te 1/32        -                 d0:43:1e:a1:d9:5d                  d0:43:1e:a1:d9:5d
 Fo 1/49        -                 fortyGigE 0/60                     90:b1:1c:f4:27:78
 Ma 1/1         -                 TenGigabitEthernet 0/13            90:b1:1c:f4:2e:8c
      LLDP_NEIGHBORS

      records = ASM::Util.parse_table(table)

      expect(records.length).to eq(20)

      expect(records[0]).to eq("Loc PortID" => "Te 1/1", "Rem Host Name" => "-", "Rem Port Id" => "24:8a:07:b9:d8:10", "Rem Chassis Id" => "24:8a:07:b9:d8:10")
      expect(records[2]).to eq("Loc PortID" => "Te 1/3", "Rem Host Name" => "localhost.local...", "Rem Port Id" => "e4:1d:2d:bf:d7:e0", "Rem Chassis Id" => "e4:1d:2d:bf:d7:e0")
      expect(records[19]).to eq("Loc PortID" => "Ma 1/1", "Rem Host Name" => "-", "Rem Port Id" => "TenGigabitEthernet 0/13", "Rem Chassis Id" => "90:b1:1c:f4:2e:8c")
    end

    it "should parse esxcli tables" do
      table = <<~LLDP_NEIGHBORS
        Name    PCI Device    Driver      Admin Status  Link Status  Speed  Duplex  MAC Address         MTU  Description
        ------  ------------  ----------  ------------  -----------  -----  ------  -----------------  ----  ----------------------------------------------------
        vmnic0  0000:18:00.0  i40en       Up            Up           10000  Full    24:6e:96:5c:d8:1c  1500  Intel(R) Ethernet Controller X710 for 10GbE SFP+
        vmnic1  0000:18:00.1  i40en       Up            Up           10000  Full    24:6e:96:5c:d8:1e  1500  Intel(R) Ethernet Controller X710 for 10GbE SFP+
        vmnic2  0000:01:00.0  igbn        Up            Down             0  Half    24:6e:96:5c:d8:3c  1500  Intel Corporation Gigabit 4P X710/I350 rNDC
        vmnic3  0000:01:00.1  igbn        Up            Down             0  Half    24:6e:96:5c:d8:3d  1500  Intel Corporation Gigabit 4P X710/I350 rNDC
        vmnic4  0000:3b:00.0  nmlx5_core  Up            Up           25000  Full    ec:0d:9a:7f:3a:96  1500  Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
        vmnic5  0000:3b:00.1  nmlx5_core  Up            Up           25000  Full    ec:0d:9a:7f:3a:97  9000  Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
        vmnic6  0000:5f:00.0  nmlx5_core  Up            Up           25000  Full    ec:0d:9a:7f:3b:46  1500  Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
        vmnic7  0000:5f:00.1  nmlx5_core  Up            Up           25000  Full    ec:0d:9a:7f:3b:47  9000  Mellanox Technologies MT27710 Family [ConnectX-4 Lx]
        vusb0   Pseudo        cdce        Up            Up             100  Full    50:9a:4c:aa:24:c9  1500  DellTM iDRAC Virtual NIC USB Device
      LLDP_NEIGHBORS

      records = ASM::Util.parse_table(table)

      expect(records.length).to eq(9)
      expect(records[0]).to eq("Name" => "vmnic0", "PCI Device" => "0000:18:00.0", "Driver" => "i40en",
                               "Admin Status" => "Up", "Link Status" => "Up", "Speed" => "10000", "Duplex" => "Full",
                               "MAC Address" => "24:6e:96:5c:d8:1c", "MTU" => "1500",
                               "Description" => "Intel(R) Ethernet Controller X710 for 10GbE SFP+")
      expect(records[8]).to eq("Name" => "vusb0", "PCI Device" => "Pseudo", "Driver" => "cdce", "Admin Status" => "Up",
                               "Link Status" => "Up", "Speed" => "100", "Duplex" => "Full", "MAC Address" => "50:9a:4c:aa:24:c9",
                               "MTU" => "1500", "Description" => "DellTM iDRAC Virtual NIC USB Device")
    end
  end
end
