# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "web-page-archiver"
  gem.homepage = "http://github.com/murb/web-page-archiver"
  gem.license = "MIT"
  gem.summary = %Q{web page archiver creates self-containing, one file, html or mhtml files}
  gem.description = %Q{web page archiver creates self-containing, one file, html or mhtml filese}
  gem.email = "github.com+web-page-archiver@murb.nl"
  gem.authors = ["takuya","murb"]
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test
