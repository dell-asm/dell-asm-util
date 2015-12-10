module ASM
  class Error                < StandardError; end
  class CommandException     < Error; end
  class SyncException        < Error; end
  class PuppetEventException < Error; end
  class NotFoundException    < Error; end
  class GraphiteException    < Error; end
  class NagiosException      < Error; end

  # A UserException message can be displayed directly to the user
  class UserException        < Error; end

  class UnconnectedServerException < Error
    attr_reader :unconnected_servers
    def initialize(servers)
      super
      @unconnected_servers = servers
    end
  end
end


