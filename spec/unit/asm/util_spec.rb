# frozen_string_literal: true

require "asm/util"
require "asm/errors"
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
           .with({"ANSIBLE_STDOUT_CALLBACK" => "json", "ANSIBLE_HOST_KEY_CHECKING" => "False"},
                 @arg1,
                 @arg2,
                 @arg3,
                 @arg4,
                 @arg5,
                 @arg6,
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
           .with({"ANSIBLE_STDOUT_CALLBACK" => "json", "ANSIBLE_HOST_KEY_CHECKING" => "False"},
                 @arg1,
                 @arg2,
                 @arg3,
                 @arg4,
                 @arg5,
                 @arg6,
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
           .with({"VAULT" => "test", "ANSIBLE_STDOUT_CALLBACK" => "json", "ANSIBLE_HOST_KEY_CHECKING" => "False"},
                 @arg1,
                 @arg2,
                 @arg3,
                 @arg4,
                 @arg5,
                 @arg6,
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
      Net::SSH::Verifiers::Null = mock("Null")
      Net::SSH::Verifiers::Null.expects(:new).returns(true)
      session = mock("session")
      channel = mock("channel")
      channel.expects(:exec).yields("test", true)
      channel.expects(:on_data).yields(nil, "test")
      channel.expects(:on_extended_data)
      channel.expects(:on_request)
      session.expects(:open_channel).at_least_once.yields(channel)
      session.expects(:loop)
      Net::SSH.expects(:start)
              .with("155.68.106.198", "root", :password => "P@ssw0rd", :verify_host_key => true, :global_known_hosts_file => "/dev/null")
              .yields(session)
      result = ASM::Util.execute_script_via_ssh("155.68.106.198", "root", "P@ssw0rd", "ls", "-lrt")
      expect(result).to eq(:exit_code => -1, :stderr => "", :stdout => "test")
    end
  end
end
