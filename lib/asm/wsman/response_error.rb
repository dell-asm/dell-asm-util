# frozen_string_literal: true

module ASM
  class WsMan
    class Error < StandardError; end

    # An exception that encapsulates a ws-man response.
    class ResponseError < StandardError
      attr_reader :response

      def initialize(msg, response)
        super(msg)
        @response = response
      end

      def to_s
        "%s: %s" % [super.to_s, Parser.response_string(response)]
      end
    end

    # An exception that encapsulates a ws-man fault message.
    class FaultError < ASM::WsMan::Error
      attr_reader :fault
      attr_reader :reason

      def initialize(fault_code, reason)
        super("WS-MAN returned a fault code: %s (%s)" % [fault_code, reason])
        @fault = fault
        @reason = reason
      end
    end
  end
end
