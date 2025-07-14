# frozen_string_literal: true

require 'rspec'
require 'fileutils'
require 'tmpdir'

# Mock Log4r for unit tests
module Log4r
  class Logger
    def initialize(name)
      @name = name
    end

    %w[debug info warn error].each do |level|
      define_method(level) do |msg|
        # no-op logging for tests
      end
    end
  end
end

# Only load classes that don't depend on Vagrant for unit tests
require_relative '../lib/vagrant_ssh_config_manager/version'
require_relative '../lib/vagrant_ssh_config_manager/file_locker'
require_relative '../lib/vagrant_ssh_config_manager/file_manager'
require_relative '../lib/vagrant_ssh_config_manager/ssh_config_manager'
require_relative '../lib/vagrant_ssh_config_manager/include_manager'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  Kernel.srand config.seed
  config.formatter = :progress
  config.profile_examples = 10

  # Minimal setup for unit tests
  config.before(:each) do
    @temp_dir = Dir.mktmpdir('unit-test')
  end

  config.after(:each) do
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end
end
