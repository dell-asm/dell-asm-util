#!/usr/bin/ruby

# frozen_string_literal: true

require "trollop"
require "pathname"
require "pry"
require "asm/wsman"

# Opens a pry console in the context of ASM::WsMan for the specified iDrac
# endpoint. From there you can easily execute any of the WsMan methods:
#
#     [delladmin@dellasm ~]$ wsman_shell.rb --server=172.17.3.211
#     [1] pry(#<ASM::WsMan>)> power_state
#     => :on

opts = Trollop.options do
  opt :server, "iDrac hostname or ip", :type => :string, :required => true
  opt :username, "iDrac username (defaul root)", :type => :string, :default => "root"
  opt :password, "iDrac password (default calvin)", :type => :string, :default => ENV["PASSWORD"] || "calvin"
  opt :debug, "Print wsman CLI executions", :type => :boolean, :default => false
end

LOGGER = opts[:debug] ? Logger.new("/dev/stdout") : Logger.new(nil)
ENDPOINT = {:host => opts[:server], :user => opts[:username], :password => opts[:password]}.freeze
WSMAN = ASM::WsMan.new(ENDPOINT, :logger => LOGGER)

def WSMAN.pry
  binding.pry :quiet => true # rubocop:disable Lint/Debugger
end

WSMAN.pry
