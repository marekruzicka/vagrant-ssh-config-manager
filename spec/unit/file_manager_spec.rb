require 'spec_helper'
require 'tempfile'
require 'tmpdir'

# Mock the Vagrant and plugin dependencies for testing
module VagrantPlugins
  module SshConfigManager
    # Mock config class for testing
    class MockConfig
      attr_accessor :ssh_config_dir, :cleanup_empty_dir, :enabled, :project_isolation

      def initialize
        @ssh_config_dir = Dir.mktmpdir('vagrant-ssh-config-test')
        @cleanup_empty_dir = true
        @enabled = true
        @project_isolation = true
      end
    end

    # Mock machine class for testing
    class MockMachine
      attr_accessor :name, :env

      def initialize(name, root_path = '/tmp/test-project')
        @name = name
        @env = OpenStruct.new(root_path: Pathname.new(root_path))
      end

      def ssh_info
        {
          host: '192.168.33.10',
          port: 22,
          username: 'vagrant',
          private_key_path: ['/tmp/test-key']
        }
      end
    end
  end
end

# Mock Log4r for testing
module Log4r
  class Logger
    def initialize(name)
      @name = name
    end

    %w[debug info warn error].each do |level|
      define_method(level) { |msg| }
    end
  end
end

require_relative '../../lib/vagrant-ssh-config-manager/file_manager'

RSpec.describe VagrantPlugins::SshConfigManager::FileManager do
  let(:config) { VagrantPlugins::SshConfigManager::MockConfig.new }
  let(:file_manager) { described_class.new(config) }
  let(:machine) { VagrantPlugins::SshConfigManager::MockMachine.new('web') }

  after do
    # Clean up test directory
    FileUtils.rm_rf(config.ssh_config_dir) if Dir.exist?(config.ssh_config_dir)
  end

  describe '#initialize' do
    it 'initializes with config' do
      expect(file_manager).to be_a(described_class)
    end
  end

  describe '#generate_filename' do
    it 'generates a unique filename for a machine' do
      filename = file_manager.generate_filename(machine)
      expect(filename).to match(/\A[a-f0-9]{8}-web\.conf\z/)
    end

    it 'generates consistent filenames for the same machine' do
      filename1 = file_manager.generate_filename(machine)
      filename2 = file_manager.generate_filename(machine)
      expect(filename1).to eq(filename2)
    end

    it 'generates different filenames for different projects' do
      machine1 = VagrantPlugins::SshConfigManager::MockMachine.new('web', '/tmp/project1')
      machine2 = VagrantPlugins::SshConfigManager::MockMachine.new('web', '/tmp/project2')

      filename1 = file_manager.generate_filename(machine1)
      filename2 = file_manager.generate_filename(machine2)

      expect(filename1).not_to eq(filename2)
    end
  end

  describe '#get_file_path' do
    it 'returns the full path for a machine config file' do
      path = file_manager.get_file_path(machine)
      expect(path).to start_with(config.ssh_config_dir)
      expect(path).to end_with('.conf')
    end
  end

  describe '#generate_ssh_config_content' do
    it 'generates valid SSH config content' do
      content = file_manager.generate_ssh_config_content(machine)

      expect(content).to include('# Managed by vagrant-ssh-config-manager plugin')
      expect(content).to include('Host ')
      expect(content).to include('HostName 192.168.33.10')
      expect(content).to include('Port 22')
      expect(content).to include('User vagrant')
      expect(content).to include('IdentityFile /tmp/test-key')
    end

    it 'returns nil when SSH info is not available' do
      allow(machine).to receive(:ssh_info).and_return(nil)
      content = file_manager.generate_ssh_config_content(machine)
      expect(content).to be_nil
    end
  end

  describe '#write_ssh_config_file' do
    it 'creates SSH config file for machine' do
      result = file_manager.write_ssh_config_file(machine)
      expect(result).to be true

      file_path = file_manager.get_file_path(machine)
      expect(File.exist?(file_path)).to be true

      content = File.read(file_path)
      expect(content).to include('Host ')
      expect(content).to include('HostName ')
    end

    it 'creates directory if it does not exist' do
      FileUtils.rm_rf(config.ssh_config_dir)
      expect(Dir.exist?(config.ssh_config_dir)).to be false

      file_manager.write_ssh_config_file(machine)
      expect(Dir.exist?(config.ssh_config_dir)).to be true
    end

    it 'sets correct file permissions' do
      file_manager.write_ssh_config_file(machine)
      file_path = file_manager.get_file_path(machine)

      file_stat = File.stat(file_path)
      expect(file_stat.mode & 0o777).to eq(0o600)
    end
  end

  describe '#remove_ssh_config_file' do
    before do
      file_manager.write_ssh_config_file(machine)
    end

    it 'removes existing SSH config file' do
      file_path = file_manager.get_file_path(machine)
      expect(File.exist?(file_path)).to be true

      result = file_manager.remove_ssh_config_file(machine)
      expect(result).to be true
      expect(File.exist?(file_path)).to be false
    end

    it 'returns false when file does not exist' do
      file_path = file_manager.get_file_path(machine)
      File.delete(file_path)

      result = file_manager.remove_ssh_config_file(machine)
      expect(result).to be false
    end

    it 'cleans up empty directory when configured' do
      config.cleanup_empty_dir = true
      file_manager.remove_ssh_config_file(machine)

      expect(Dir.exist?(config.ssh_config_dir)).to be false
    end
  end

  describe '#ssh_config_file_exists?' do
    it 'returns true when file exists' do
      file_manager.write_ssh_config_file(machine)
      expect(file_manager.ssh_config_file_exists?(machine)).to be true
    end

    it 'returns false when file does not exist' do
      expect(file_manager.ssh_config_file_exists?(machine)).to be false
    end
  end

  describe '#validate_ssh_config_content' do
    it 'validates valid SSH config content' do
      valid_content = "Host test\n  HostName 192.168.1.1\n  Port 22"
      expect(file_manager.validate_ssh_config_content(valid_content)).to be true
    end

    it 'rejects invalid SSH config content' do
      expect(file_manager.validate_ssh_config_content(nil)).to be false
      expect(file_manager.validate_ssh_config_content('')).to be false
      expect(file_manager.validate_ssh_config_content('invalid content')).to be false
    end
  end

  describe '#cleanup_orphaned_files' do
    let(:machine2) { VagrantPlugins::SshConfigManager::MockMachine.new('db') }

    it 'cleans up orphaned files' do
      # Create files for two machines
      file_manager.write_ssh_config_file(machine)
      file_manager.write_ssh_config_file(machine2)

      # Only one machine is active
      active_machines = [machine]

      cleaned_count = file_manager.cleanup_orphaned_files(active_machines)
      expect(cleaned_count).to eq(1)

      # Active machine file should still exist
      expect(file_manager.ssh_config_file_exists?(machine)).to be true
      # Orphaned file should be removed
      expect(file_manager.ssh_config_file_exists?(machine2)).to be false
    end

    it 'does not remove files for active machines' do
      file_manager.write_ssh_config_file(machine)

      active_machines = [machine]
      cleaned_count = file_manager.cleanup_orphaned_files(active_machines)

      expect(cleaned_count).to eq(0)
      expect(file_manager.ssh_config_file_exists?(machine)).to be true
    end
  end
end
