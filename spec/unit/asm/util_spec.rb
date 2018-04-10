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
    esxcli_thumbprint_msg = <<-eos
Connect to 100.1.1.100 failed. Server SHA-1 thumbprint: 28:C6:8D:54:1B:08:A1:08:7A:0B:50:6D:B7:73:06:96:71:A1:6D:03 (not trusted).
    eos
    err_result = {
      "exit_status" => 1,
      "stdout" => esxcli_thumbprint_msg
    }

    stdout = <<-eos
Name                    Virtual Switch  Active Clients  VLAN ID
----------------------  --------------  --------------  -------
ISCSI0                  vSwitch3                     1       16
ISCSI1                  vSwitch3                     1       16
Management Network      vSwitch0                     1        0
Management Network (1)  vSwitch0                     1       28
VM Network              vSwitch0                     1        0
Workload Network        vSwitch2                     0       20
vMotion                 vSwitch1                     1       23

    eos
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
    stdout = <<-eos
Name                    Virtual Switch  Active Clients  VLAN ID
----------------------  --------------  --------------  -------
ISCSI0                  vSwitch3                     1       16
ISCSI1                  vSwitch3                     1       16
Management Network      vSwitch0                     1        0
Management Network (1)  vSwitch0                     1       28
VM Network              vSwitch0                     1        0
Workload Network        vSwitch2                     0       20
vMotion                 vSwitch1                     1       23

    eos
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

  describe '#hostname_to_certname' do
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
               .returns(<<EOF
192.168.253.100 dev ens192 src 192.168.253.1
    cache

EOF
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
               .returns(<<EOF
default via 100.68.107.190 dev ens160 proto static metric 100
100.68.107.128/26 dev ens160 proto kernel scope link src 100.68.107.160 metric 100
192.168.253.0/24 dev ens192 proto kernel scope link src 192.168.253.1 metric 100

EOF
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
end
