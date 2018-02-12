dir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift File.join(dir, "lib")

# Don't want puppet getting the command line arguments for rake or autotest
ARGV.clear

if ENV["CI"] == "true" && RUBY_PLATFORM != "java" && Integer(RUBY_VERSION.split(".").first) > 1
  require "simplecov"
  require "coveralls"

  SimpleCov.formatter = Coveralls::SimpleCov::Formatter
  SimpleCov.start do
    add_filter "spec"
  end
end

require "facter"
require "mocha/api"
gem "rspec", ">=2.0.0"
require "rspec/expectations"
require "puppetlabs_spec_helper/module_spec_helper"

module SpecHelper
  FIXTURE_PATH = File.expand_path(File.join(File.dirname(__FILE__), "fixtures"))

  def self.load_fixture(fixture)
    File.read(File.join(FIXTURE_PATH, fixture))
  end
end
