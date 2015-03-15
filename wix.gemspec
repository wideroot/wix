# Ensure we require the local version and not one we might have installed already
require File.join([File.dirname(__FILE__),'lib','wix','version.rb'])
spec = Gem::Specification.new do |s| 
  s.name = 'wix'
  s.version = Wix::VERSION
  s.author = 'Koj'
  s.email = 'koovja@gmail.com'
  s.homepage = 'https://github.com/wideroot'
  s.platform = Gem::Platform::RUBY
  s.summary = 'windex clinet'
  s.files = `git ls-files`.split("
")
  s.require_paths << 'lib'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.md']
  s.rdoc_options << '--title' << 'wix' << '--main' << 'README.md' << '-ri'
  s.bindir = 'bin'
  s.executables << 'wix'
  s.add_development_dependency('rake')
  s.add_development_dependency('rdoc')
  s.add_development_dependency('aruba')
  s.add_runtime_dependency('gli','2.13.0')
end
