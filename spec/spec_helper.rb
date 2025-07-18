# frozen_string_literal: true

require 'rspec'
require 'fileutils'
require 'tmpdir'

# Mock Log4r for all tests
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

# Only load classes that don't depend on Vagrant
require_relative '../lib/vagrant_ssh_config_manager/version'
require_relative '../lib/vagrant_ssh_config_manager/file_locker'

# NOTE: We don't load ssh_config_manager here as it depends on Vagrant
# Instead, we'll test core functionality independently

RSpec.configure do |config|
  # Use the expect syntax (not the should syntax)
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  # Use the new mock syntax
  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option
  Kernel.srand config.seed

  # Configure output format
  config.formatter = :progress

  # Show the 10 slowest examples and example groups at the end of the spec run
  config.profile_examples = 10

  # Shared setup for all tests
  config.before(:each) do
    # Create a temporary directory for each test
    @temp_dir = Dir.mktmpdir('vagrant-ssh-config-manager-test')
    @original_env = ENV.to_hash

    # Set up test environment
    ENV['HOME'] = @temp_dir

    # Create SSH directory structure
    @ssh_dir = File.join(@temp_dir, '.ssh')
    FileUtils.mkdir_p(@ssh_dir, mode: 0o700)

    @ssh_config_file = File.join(@ssh_dir, 'config')
    @config_d_dir = File.join(@ssh_dir, 'config.d')
  end

  config.after(:each) do
    # Clean up temporary directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)

    # Restore original environment
    ENV.clear
    ENV.update(@original_env)
  end

  # Helper methods available in all tests
  config.include(Module.new do
    # Read SSH config file
    def read_ssh_config
      File.exist?(@ssh_config_file) ? File.read(@ssh_config_file) : ''
    end

    # List SSH config entries from config.d directory
    def include_files
      return [] unless File.directory?(@config_d_dir)

      Dir.glob(File.join(@config_d_dir, 'vagrant-*'))
    end
    alias_method :get_include_files, :include_files
  end)
end
