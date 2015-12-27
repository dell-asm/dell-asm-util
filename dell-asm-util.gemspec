Gem::Specification.new do |s|
  s.name        = 'dell-asm-util'
  s.version     = '0.1.0'
  s.licenses    = ['Dell 2015']
  s.summary     = 'Util classes for Dell ASM and ASM Puppet Modules'
  s.description = 'Util classes for Dell ASM and ASM Puppet Modules'
  s.authors     = ['Dell']
  s.email       = 'asm@dell.com'
  s.homepage    = 'https://github.com/dell-asm/dell-asm-util'


  s.add_dependency 'aescrypt', '~> 1.0.0'
  s.add_dependency 'hashie', '>= 2.0.5'
  s.add_dependency 'trollop', '~> 2.0'
  s.add_dependency 'nokogiri', '~> 1.5.10'
  s.add_dependency 'i18n', '~> 0.6.5'

  s.add_development_dependency 'logger-colors', '~> 1.0.0'
  s.add_development_dependency 'guard-shell'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'kramdown'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rspec', '~>2.14.0'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'puppet'
  s.add_development_dependency 'puppetlabs_spec_helper', '0.4.1'

  s.files        = Dir.glob("lib/**/*")
  s.require_path = 'lib'
end