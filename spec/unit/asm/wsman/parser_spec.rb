# frozen_string_literal: true

require "spec_helper"
require "asm/wsman/parser"

describe ASM::WsMan::Parser do
  let(:parser) {ASM::WsMan::Parser}

  describe "#response_string" do
    it "should display message" do
      resp = {:lcstatus => "5",
              :message => "Lifecycle Controller Remote Services is not ready."}
      expect(parser.response_string(resp)).to eq("Lifecycle Controller Remote Services is not ready. [lcstatus: 5]")
    end
  end

  describe "#parse" do
    it "should parse simple responses" do
      content = SpecHelper.load_fixture("wsman/get_attach_status.xml")
      expect(parser.parse(content)).to eq(:return_value => "0")
    end

    it "should parse job status responses" do
      content = SpecHelper.load_fixture("wsman/connect_network_iso.xml")
      expected = {:job => "DCIM_OSDConcreteJob:1",
                  :return_value => "4096"}
      expect(parser.parse(content)).to eq(expected)
    end

    it "should parse faults" do
      content = SpecHelper.load_fixture("wsman/fault.xml")
      expect {parser.parse(content)}.to raise_error(ASM::WsMan::FaultError, "WS-MAN returned a fault code: wsman:InvalidParameter (CMPI_RC_ERR_INVALID_PARAMETER)")
    end

    it "should parse timed out fault" do
      content = SpecHelper.load_fixture("wsman/timed_out_fault.xml")
      expect {parser.parse(content)}.to raise_error(ASM::WsMan::FaultError, "WS-MAN returned a fault code: wsman:TimedOut (The operation has timed out.)")
    end

    it "should parse xsi:nil elements" do
      content = SpecHelper.load_fixture("wsman/osd_concrete_job.xml")
      expected = {:delete_on_completion => "false",
                  :instance_id => "DCIM_OSDConcreteJob:1",
                  :job_name => "BootToNetworkISO",
                  :job_status => "Rebooting to ISO",
                  :message => nil,
                  :message_id => nil,
                  :name => "BootToNetworkISO"}
      expect(parser.parse(content)).to eq(expected)
    end
  end

  describe "#parse_enumeration" do
    it "should parse the enumeration content" do
      content = SpecHelper.load_fixture("wsman/boot_config_setting.txt")
      ret = parser.parse_enumeration(content)
      expect(ret.size).to eq(5)
      expect(ret[0]).to eq(:element_name => "BootSeq",
                           :instance_id => "IPL",
                           :is_current => "1",
                           :is_default => "0",
                           :is_next => "1")
    end

    it "should parse a fault response" do
      content = SpecHelper.load_fixture("wsman/fault.xml")
      expect {parser.parse_enumeration(content)}.to raise_error(ASM::WsMan::FaultError, "WS-MAN returned a fault code: wsman:InvalidParameter (CMPI_RC_ERR_INVALID_PARAMETER)")
    end
  end

  describe "#camel_case" do
    it "should not change single word" do
      expect(parser.camel_case("foo")).to eq("foo")
    end

    it "should capitalize 2nd word" do
      expect(parser.camel_case("foo_bar")).to eq("fooBar")
    end

    it "should capitalize 2nd and greater words" do
      expect(parser.camel_case("foo_bar_baz")).to eq("fooBarBaz")
    end

    it "should capitalize first letter if asked" do
      expect(parser.camel_case("foo_bar", :capitalize => true)).to eq("FooBar")
    end
  end

  describe "#snake_case" do
    it "should not change single word" do
      expect(parser.snake_case("foo")).to eq("foo")
    end

    it "should lower-case and add underscore before 2nd word" do
      expect(parser.snake_case("fooBar")).to eq("foo_bar")
    end

    it "should lower-case and add underscore before 2nd and greater words" do
      expect(parser.snake_case("fooBarBaz")).to eq("foo_bar_baz")
    end

    it "should not begin with an underscore if original did not" do
      expect(parser.snake_case("ReturnValue")).to eq("return_value")
    end

    it "should begin with an underscore if original value did" do
      expect(parser.snake_case("__cimnamespace")).to eq("__cimnamespace")
    end

    it "should treat multiple capitalized characters as a single word" do
      expect(parser.snake_case("JobID")).to eq("job_id")
    end

    it "should handle ISO as a single word" do
      expect(parser.snake_case("ISOAttachStatus")).to eq("iso_attach_status")
    end

    it "should handle fcoe and wwnn as single words" do
      expect(parser.snake_case("FCoEWWNN")).to eq("fcoe_wwnn")
    end

    it "should handle MAC as a single word" do
      expect(parser.snake_case("PermanentFCOEMACAddress")).to eq("permanent_fcoe_mac_address")
    end
  end

  describe "#enum_value" do
    it "should accept and convert keys to values" do
      expect(parser.enum_value(:share_type, {:foo => "a", :bar => "b"}, :foo)).to eq("a")
    end

    it "should accept values" do
      expect(parser.enum_value(:share_type, {:foo => "a", :bar => "b"}, "b")).to eq("b")
    end

    it "should accept fixnum " do
      expect(parser.enum_value(:share_type, {:foo => "a", :bar => "0"}, 0)).to eq("0")
    end

    it "should fail for unknown values" do
      expect do
        parser.enum_value(:share_type, {:foo => "a", :bar => "b"}, :unknown)
      end.to raise_error("Invalid share_type value: unknown; allowed values are: :foo (a), :bar (b)")
    end
  end

  describe "#wsman_value" do
    it "should convert :share_type" do
      parser.expects(:enum_value).with(:share_type, {:nfs => "0", :cifs => "2"}, :cifs).returns("2")
      expect(parser.wsman_value(:share_type, :cifs)).to eq("2")
    end

    it "should convert :hash_type" do
      parser.expects(:enum_value).with(:hash_type, {:md5 => "1", :sha1 => "2"}, :md5).returns("1")
      expect(parser.wsman_value(:hash_type, :md5)).to eq("1")
    end

    it "should pass through other keys" do
      expect(parser.wsman_value(:foo, "foo")).to eq("foo")
    end
  end
end
