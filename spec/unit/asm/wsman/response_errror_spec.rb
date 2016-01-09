require "spec_helper"
require "asm/wsman/response_error"

describe ASM::WsMan::ResponseError do
  describe "ResponseError#to_s" do
    it "should display message" do
      e = ASM::WsMan::ResponseError.new("Exception message", :message => "ws-man message", :message_id => "4")
      expect(e.to_s).to eq("Exception message: ws-man message [message_id: 4]")
    end

    it "should display fault reason" do
      e = ASM::WsMan::ResponseError.new("Exception message", :reason => "ws-man fault reason", :message_id => "4")
      expect(e.to_s).to eq("Exception message: ws-man fault reason [message_id: 4]")
    end

    it "should prefer message to fault reason" do
      resp = {:message => "ws-man message", :reason => "ws-man fault reason", :message_id => "4"}
      e = ASM::WsMan::ResponseError.new("Exception message", resp)
      expect(e.to_s).to eq("Exception message: ws-man message [reason: ws-man fault reason, message_id: 4]")
    end
  end
end
