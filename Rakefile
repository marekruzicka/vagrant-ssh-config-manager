# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

# Unit and integration specs must run in separate Ruby processes.
# Integration specs load the real Vagrant gem which defines
# Vagrant::Plugin::V2::Config as a class; unit specs mock it as a
# module, causing TypeError when loaded in the same process.
namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = 'spec/unit/**/*_spec.rb'
  end

  RSpec::Core::RakeTask.new(:integration) do |t|
    t.pattern = 'spec/integration/**/*_spec.rb'
  end
end

desc 'Run all specs (unit + integration in separate processes)'
task spec: ['spec:unit', 'spec:integration']

task default: :spec

desc 'Run RuboCop'
task :rubocop do
  sh 'bundle exec rubocop'
end

desc 'Run RuboCop with auto-correct'
task :rubocop_fix do
  sh 'bundle exec rubocop -a'
end

desc 'Run tests with coverage'
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end
