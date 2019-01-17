Gem::Specification.new do |s|
  s.name        = "dell-asm-util"
  s.version     = "0.1.0"
  s.licenses    = ["Dell 2015-2018"]
  s.summary     = "Util classes for Dell ASM and ASM Puppet Modules"
  s.description = "Util classes for Dell ASM and ASM Puppet Modules"
  s.authors     = ["Dell"]
  s.email       = "asm@dell.com"
  s.homepage    = "https://github.com/dell-asm/dell-asm-util"

  s.add_dependency "aescrypt"
  s.add_dependency "hashie"
  s.add_dependency "trollop"
  s.add_dependency "i18n"
  s.add_dependency "pry"
  s.add_dependency "rest-client"
  s.add_dependency "net-ssh"
  s.add_dependency "nokogiri", "<= 1.8.4"

  s.add_development_dependency "listen"
  s.add_development_dependency "rake", "12.2.1"
  s.add_development_dependency "logger-colors"
  s.add_development_dependency "guard-shell"
  s.add_development_dependency "yard"
  s.add_development_dependency "kramdown"
  s.add_development_dependency "rainbow"
  s.add_development_dependency "rubocop", "0.37.2"
  s.add_development_dependency "rspec"
  s.add_development_dependency "mocha"
  s.add_development_dependency "puppet"
  s.add_development_dependency "puppetlabs_spec_helper", "0.4.1"
  s.add_development_dependency "json_pure"
  s.add_development_dependency "coveralls" if Integer(RUBY_VERSION.split(".").first) > 1

  s.executables << "wsman_shell.rb"

  s.files        = Dir.glob("lib/**/*")
  s.require_path = "lib"
end
