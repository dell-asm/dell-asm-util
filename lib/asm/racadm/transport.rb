require "asm/util"
require "logger"
require "net/ssh"

module ASM
  class Racadm
    class Transport
      attr_reader :endpoint

      def initialize(endpoint)
        missing_params = [:host, :user, :password].reject { |k| endpoint.include?(k) }
        raise("Missing required endpoint parameter(s): %s" % [missing_params.join(",")]) unless missing_params.empty?
        @endpoint = endpoint
      end

      def client
        return @client if @client && !@client.closed?
        @client = Net::SSH.start(
          endpoint[:host],
          endpoint[:user],
          :password => endpoint[:password],
          :paranoid => Net::SSH::Verifiers::Null.new,
          :global_known_hosts_file => "/dev/null"
        )
      end
    end
  end
end
