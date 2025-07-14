# frozen_string_literal: true

require 'rspec'
require 'fileutils'
require 'tmpdir'
require 'pathname'

# Load real Vagrant for integration tests
require 'vagrant'

# Load our plugin classes
require_relative '../lib/vagrant_ssh_config_manager/version'
require_relative '../lib/vagrant_ssh_config_manager/file_locker'
require_relative '../lib/vagrant_ssh_config_manager/config'
require_relative '../lib/vagrant_ssh_config_manager/file_manager'
require_relative '../lib/vagrant_ssh_config_manager/include_manager'
require_relative '../lib/vagrant_ssh_config_manager/ssh_config_manager'

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

  # Integration test setup with real file system
  config.before(:each) do
    @temp_dir = Dir.mktmpdir('integration-test')
    @original_env = ENV.to_hash

    # Set up isolated test environment
    ENV['HOME'] = @temp_dir

    # Create SSH directory structure
    @ssh_dir = File.join(@temp_dir, '.ssh')
    FileUtils.mkdir_p(@ssh_dir, mode: 0o700)

    @ssh_config_file = File.join(@ssh_dir, 'config')
    @config_d_dir = File.join(@ssh_dir, 'config.d')
    @vagrant_config_dir = File.join(@config_d_dir, 'vagrant')

    FileUtils.mkdir_p(@vagrant_config_dir, mode: 0o700)
  end

  config.after(:each) do
    # Clean up
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)

    # Restore environment
    ENV.clear
    ENV.update(@original_env)
  end

  # Helper methods for integration tests
  config.include(Module.new do
    def create_test_machine(name, root_path = @temp_dir)
      env = double('environment')
      allow(env).to receive(:root_path).and_return(Pathname.new(root_path))

      machine = double('machine')
      allow(machine).to receive(:name).and_return(name)
      allow(machine).to receive(:env).and_return(env)
      allow(machine).to receive(:ssh_info).and_return({
                                                        host: '192.168.33.10',
                                                        port: 22,
                                                        username: 'vagrant',
                                                        private_key_path: [File.join(@temp_dir, 'private_key')]
                                                      })

      machine
    end

    def create_test_config
      config = VagrantPlugins::SshConfigManager::Config.new
      config.ssh_config_dir = @vagrant_config_dir
      config.manage_includes = true
      config.auto_create_dir = true
      config.cleanup_empty_dir = true
      config.ssh_conf_file = nil # Will use default ~/.ssh/config
      config.finalize!
      config
    end

    def read_ssh_config
      File.exist?(@ssh_config_file) ? File.read(@ssh_config_file) : ''
    end

    def include_files
      return [] unless File.directory?(@vagrant_config_dir)

      Dir.glob(File.join(@vagrant_config_dir, '*'))
    end
  end)
end
