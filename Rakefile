require 'rubygems'
require 'puppetlabs_spec_helper/rake_tasks'
require 'rake'
require 'rspec/core/rake_task'

Dir.glob('tasks/*.rake').each { |r| load r}

RSpec::Core::RakeTask.new(:spec)

# Run unit tests by default
task :default => 'spec:suite:unit'

# To run unit tests:                 bundle exec rake spec:suite:unit

namespace :spec do
  namespace :suite do
    desc 'Run all specs in unit spec suite'
    RSpec::Core::RakeTask.new('unit') do |t|
      t.pattern = './spec/unit/**/*_spec.rb'
    end
  end
end

namespace :doc do
  desc "Serve YARD documentation on %s:%d" % [ENV.fetch("YARD_BIND", "127.0.0.1"), ENV.fetch("YARD_PORT", "9293")]
  task :serve do
    system("yard server --reload --bind %s --port %d" % [ENV.fetch("YARD_BIND", "127.0.0.1"), ENV.fetch("YARD_PORT", "9293")])
  end

  desc "Generate documentatin into the %s" % ENV.fetch("YARD_OUT", "doc")
  task :yard do
    system("yard doc --output-dir %s" % ENV.fetch("YARD_OUT", "doc"))
  end
end
