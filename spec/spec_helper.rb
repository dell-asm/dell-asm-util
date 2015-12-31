dir = File.expand_path(File.dirname(__FILE__))
$LOAD_PATH.unshift File.join(dir, "lib")

# Don't want puppet getting the command line arguments for rake or autotest
ARGV.clear

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

  def self.init_i18n
    I18n.load_path = Dir[File.expand_path(File.join(File.dirname(__FILE__), "..", "locales", "*.yml"))]
    I18n.locale = "en".intern
  end
end
