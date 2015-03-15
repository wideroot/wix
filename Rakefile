require 'rake/clean'
require 'rubygems'
require 'rubygems/package_task'
require 'rdoc/task'
Rake::RDocTask.new do |rd|
  rd.main = "README.md"
  rd.rdoc_files.include("README.md","lib/**/*.rb","bin/**/*")
  rd.title = 'windex client'
end

spec = eval(File.read('wix.gemspec'))

Gem::PackageTask.new(spec) do |pkg|
end
CUKE_RESULTS = 'results.html'
CLEAN << CUKE_RESULTS
