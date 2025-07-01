require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc "Run RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Run RuboCop with auto-correct"
task :rubocop_fix do
  sh "bundle exec rubocop -a"
end

desc "Run tests with coverage"
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end
