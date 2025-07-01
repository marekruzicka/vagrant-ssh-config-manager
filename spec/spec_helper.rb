require 'rspec'
require 'vagrant'
require 'fileutils'
require 'tmpdir'

# Load our plugin
require_relative '../lib/vagrant-ssh-config-manager'

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

  # Filter lines from Rails gems in backtraces
  config.filter_rails_from_backtrace!

  # Shared setup for all tests
  config.before(:each) do
    # Create a temporary directory for each test
    @temp_dir = Dir.mktmpdir('vagrant-ssh-config-manager-test')
    @original_env = ENV.to_hash
    
    # Set up test environment
    ENV['HOME'] = @temp_dir
    
    # Create SSH directory structure
    @ssh_dir = File.join(@temp_dir, '.ssh')
    FileUtils.mkdir_p(@ssh_dir, mode: 0700)
    
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
  config.include Module.new {
    # Create a mock Vagrant machine
    def create_mock_machine(name: 'test-vm', provider: 'virtualbox', config: nil)
      machine = double('machine')
      allow(machine).to receive(:name).and_return(name)
      allow(machine).to receive(:provider_name).and_return(provider)
      
      # Mock UI
      ui = double('ui')
      allow(ui).to receive(:info)
      allow(ui).to receive(:warn)
      allow(ui).to receive(:error)
      allow(machine).to receive(:ui).and_return(ui)
      
      # Mock state
      state = double('state')
      allow(state).to receive(:id).and_return(:running)
      allow(machine).to receive(:state).and_return(state)
      
      # Mock config
      ssh_config_manager_config = config || create_mock_config
      machine_config = double('config')
      allow(machine_config).to receive(:sshconfigmanager).and_return(ssh_config_manager_config)
      allow(machine).to receive(:config).and_return(machine_config)
      
      # Mock SSH info
      ssh_info = {
        host: '127.0.0.1',
        port: 2222,
        username: 'vagrant',
        private_key_path: ['/path/to/private_key']
      }
      allow(machine).to receive(:ssh_info).and_return(ssh_info)
      
      # Mock communicator
      communicator = double('communicator')
      allow(communicator).to receive(:ready?).and_return(true)
      allow(machine).to receive(:communicate).and_return(communicator)
      
      # Mock environment
      env = double('env')
      allow(env).to receive(:root_path).and_return('/path/to/vagrant/project')
      allow(machine).to receive(:env).and_return(env)
      
      machine
    end

    # Create a mock configuration
    def create_mock_config(overrides = {})
      config = double('config')
      
      defaults = {
        enabled: true,
        ssh_conf_file: @ssh_config_file,
        auto_remove_on_destroy: true,
        update_on_reload: true,
        refresh_on_provision: true,
        keep_config_on_halt: true,
        project_isolation: true
      }
      
      final_config = defaults.merge(overrides)
      
      final_config.each do |key, value|
        allow(config).to receive(key).and_return(value)
      end
      
      # Mock helper methods
      allow(config).to receive(:enabled_for_action?).and_return(true)
      allow(config).to receive(:effective_ssh_config_file).and_return(@ssh_config_file)
      
      config
    end

    # Create test SSH config content
    def create_test_ssh_config(entries = [])
      content = "# Test SSH Config\n\n"
      
      entries.each do |entry|
        content += "Host #{entry[:host]}\n"
        content += "  HostName #{entry[:hostname]}\n"
        content += "  Port #{entry[:port]}\n"
        content += "  User #{entry[:user]}\n"
        content += "  IdentityFile #{entry[:identity_file]}\n"
        content += "\n"
      end
      
      content
    end

    # Write test SSH config file
    def write_test_ssh_config(content = nil)
      content ||= create_test_ssh_config
      File.write(@ssh_config_file, content)
      File.chmod(0600, @ssh_config_file)
    end

    # Read SSH config file
    def read_ssh_config
      File.exist?(@ssh_config_file) ? File.read(@ssh_config_file) : ""
    end

    # Get SSH config entries from config.d directory
    def get_include_files
      return [] unless File.directory?(@config_d_dir)
      Dir.glob(File.join(@config_d_dir, 'vagrant-*')).sort
    end
  }
end

# Load shared examples and support files
Dir[File.expand_path('../support/**/*.rb', __FILE__)].each { |f| require f }
