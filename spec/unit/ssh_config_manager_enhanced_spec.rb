# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'tmpdir'

# Enhanced mock classes for SshConfigManager testing
module VagrantPlugins
  module SshConfigManager
    # Mock config class for testing SshConfigManager
    class MockConfigForSshConfigManager
      attr_accessor :ssh_config_dir, :manage_includes, :cleanup_empty_dir,
                    :auto_create_dir, :auto_remove_on_destroy, :ssh_conf_file

      def initialize
        @ssh_config_dir = File.join(Dir.mktmpdir('vagrant-ssh-config-test'), 'config.d')
        @manage_includes = true
        @cleanup_empty_dir = true
        @auto_create_dir = true
        @auto_remove_on_destroy = true
        @ssh_conf_file = nil  # Add the missing attribute
      end
    end

    # Mock machine class for testing SshConfigManager
    class MockMachineForSshConfigManager
      attr_accessor :name, :env

      def initialize(name, root_path = '/tmp/test-project')
        @name = name
        env_struct = Struct.new(:root_path)
        @env = env_struct.new(Pathname.new(root_path))
      end

      def ssh_info
        {
          host: '192.168.33.10',
          port: 22,
          username: 'vagrant',
          private_key_path: ['/tmp/test-key']
        }
      end

      def config
        config_struct = Struct.new(:sshconfigmanager)
        mock_config = MockConfigForSshConfigManager.new
        config_struct.new(mock_config)
      end
    end
  end
end

require_relative '../../lib/vagrant_ssh_config_manager/ssh_config_manager'

RSpec.describe VagrantPlugins::SshConfigManager::SshConfigManager do
  let(:machine) { VagrantPlugins::SshConfigManager::MockMachineForSshConfigManager.new('web') }
  let(:config) { machine.config.sshconfigmanager }
  let(:ssh_config_manager) { described_class.new(machine, config) }

  before do
    # Create SSH directory structure
    FileUtils.mkdir_p(config.ssh_config_dir, mode: 0o700)
  end

  after do
    # Clean up test directories
    FileUtils.rm_rf(File.dirname(config.ssh_config_dir))
  end

  describe '#initialize' do
    it 'initializes with machine and config' do
      expect(ssh_config_manager).to be_a(described_class)
    end

    it 'uses machine config when no config provided' do
      manager = described_class.new(machine)
      expect(manager).to be_a(described_class)
    end

    it 'generates project name from machine environment' do
      expect(ssh_config_manager.project_name).to be_a(String)
      expect(ssh_config_manager.project_name).not_to be_empty
    end
  end

  describe '#add_ssh_entry' do
    let(:ssh_config_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22',
        'User' => 'vagrant',
        'IdentityFile' => '/tmp/test-key'
      }
    end

    it 'adds SSH entry successfully' do
      result = ssh_config_manager.add_ssh_entry(ssh_config_data)
      expect(result).to be true
    end

    it 'creates include file with proper content' do
      ssh_config_manager.add_ssh_entry(ssh_config_data)

      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      expect(File.exist?(include_file_path)).to be true

      content = File.read(include_file_path)
      expect(content).to include('Host test-host')
      expect(content).to include('HostName 192.168.33.10')
      expect(content).to include('Port 22')
      expect(content).to include('User vagrant')
    end

    it 'returns false for invalid SSH config data' do
      expect(ssh_config_manager.add_ssh_entry(nil)).to be false
      expect(ssh_config_manager.add_ssh_entry({})).to be false
      expect(ssh_config_manager.add_ssh_entry({ 'HostName' => 'test' })).to be false
    end

    it 'handles file creation errors gracefully' do
      # Make directory read-only to simulate permission error
      File.chmod(0o500, config.ssh_config_dir)

      result = ssh_config_manager.add_ssh_entry(ssh_config_data)
      expect(result).to be false

      # Restore permissions for cleanup
      File.chmod(0o700, config.ssh_config_dir)
    end
  end

  describe '#remove_ssh_entry' do
    let(:ssh_config_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22',
        'User' => 'vagrant'
      }
    end

    before do
      ssh_config_manager.add_ssh_entry(ssh_config_data)
    end

    it 'removes SSH entry successfully' do
      result = ssh_config_manager.remove_ssh_entry('test-host')
      expect(result).to be true

      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      content = File.read(include_file_path)
      expect(content).not_to include('Host test-host')
    end

    it 'returns false for non-existent host' do
      expect(ssh_config_manager.remove_ssh_entry('non-existent')).to be false
    end

    it 'returns false for invalid host name' do
      expect(ssh_config_manager.remove_ssh_entry(nil)).to be false
      expect(ssh_config_manager.remove_ssh_entry('')).to be false
    end
  end

  describe '#update_ssh_entry' do
    let(:original_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22',
        'User' => 'vagrant'
      }
    end

    let(:updated_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.20',
        'Port' => '2222',
        'User' => 'ubuntu'
      }
    end

    before do
      ssh_config_manager.add_ssh_entry(original_data)
    end

    it 'updates SSH entry successfully' do
      result = ssh_config_manager.update_ssh_entry(updated_data)
      expect(result).to be true

      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      content = File.read(include_file_path)
      expect(content).to include('HostName 192.168.33.20')
      expect(content).to include('Port 2222')
      expect(content).to include('User ubuntu')
    end

    it 'returns false for invalid data' do
      expect(ssh_config_manager.update_ssh_entry(nil)).to be false
      expect(ssh_config_manager.update_ssh_entry({})).to be false
    end
  end

  describe '#ssh_entry_exists?' do
    let(:ssh_config_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22'
      }
    end

    it 'returns false when no entries exist' do
      expect(ssh_config_manager.ssh_entry_exists?('test-host')).to be false
    end

    it 'returns true when entry exists' do
      ssh_config_manager.add_ssh_entry(ssh_config_data)
      expect(ssh_config_manager.ssh_entry_exists?('test-host')).to be true
    end

    it 'returns false for non-existent host' do
      ssh_config_manager.add_ssh_entry(ssh_config_data)
      expect(ssh_config_manager.ssh_entry_exists?('other-host')).to be false
    end

    it 'handles file read errors gracefully' do
      # Create and then remove the include file to simulate read error
      ssh_config_manager.add_ssh_entry(ssh_config_data)
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      File.chmod(0o000, include_file_path)

      expect(ssh_config_manager.ssh_entry_exists?('test-host')).to be false

      # Restore permissions for cleanup
      File.chmod(0o600, include_file_path)
    end
  end

  describe '#project_ssh_entries' do
    let(:ssh_entries) do
      [
        {
          'Host' => 'web-host',
          'HostName' => '192.168.33.10',
          'Port' => '22',
          'User' => 'vagrant'
        },
        {
          'Host' => 'db-host',
          'HostName' => '192.168.33.11',
          'Port' => '22',
          'User' => 'vagrant'
        }
      ]
    end

    it 'returns empty array when no entries exist' do
      expect(ssh_config_manager.project_ssh_entries).to eq([])
    end

    it 'returns all SSH entries for the project' do
      ssh_entries.each { |entry| ssh_config_manager.add_ssh_entry(entry) }

      entries = ssh_config_manager.project_ssh_entries
      expect(entries.length).to eq(2)

      hosts = entries.map { |entry| entry['Host'] }
      expect(hosts).to include('web-host', 'db-host')
    end

    it 'parses SSH config format correctly' do
      ssh_config_manager.add_ssh_entry(ssh_entries.first)

      entries = ssh_config_manager.project_ssh_entries
      entry = entries.first

      expect(entry['Host']).to eq('web-host')
      expect(entry['HostName']).to eq('192.168.33.10')
      expect(entry['Port']).to eq('22')
      expect(entry['User']).to eq('vagrant')
    end

    it 'handles malformed include file gracefully' do
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      File.write(include_file_path, "Invalid content\nNot SSH format\n")

      expect(ssh_config_manager.project_ssh_entries).to eq([])
    end

    it 'provides backward compatibility alias' do
      ssh_config_manager.add_ssh_entry(ssh_entries.first)

      expect(ssh_config_manager.get_project_ssh_entries).to eq(ssh_config_manager.project_ssh_entries)
    end
  end

  describe '#include_file_info' do
    it 'returns info for non-existent file' do
      info = ssh_config_manager.include_file_info

      expect(info[:exists]).to be false
      expect(info[:size]).to eq(0)
      expect(info[:entries_count]).to eq(0)
      expect(info[:last_modified]).to be_nil
      expect(info[:path]).to be_a(String)
    end

    it 'returns info for existing file' do
      ssh_data = {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22'
      }
      ssh_config_manager.add_ssh_entry(ssh_data)

      info = ssh_config_manager.include_file_info

      expect(info[:exists]).to be true
      expect(info[:size]).to be > 0
      expect(info[:entries_count]).to be > 0
      expect(info[:last_modified]).to be_a(Time)
    end
  end

  describe '#backup_include_file' do
    let(:ssh_config_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22'
      }
    end

    it 'returns nil when include file does not exist' do
      expect(ssh_config_manager.backup_include_file).to be_nil
    end

    it 'creates backup of existing include file' do
      ssh_config_manager.add_ssh_entry(ssh_config_data)

      backup_path = ssh_config_manager.backup_include_file
      expect(backup_path).to be_a(String)
      expect(File.exist?(backup_path)).to be true

      # Backup should contain same content as original
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      original_content = File.read(include_file_path)
      backup_content = File.read(backup_path)
      expect(backup_content).to eq(original_content)

      # Clean up backup
      File.delete(backup_path)
    end

    it 'handles backup creation errors gracefully' do
      ssh_config_manager.add_ssh_entry(ssh_config_data)

      # Make source file unreadable
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      File.chmod(0o000, include_file_path)

      expect(ssh_config_manager.backup_include_file).to be_nil

      # Restore permissions
      File.chmod(0o600, include_file_path)
    end
  end

  describe '#restore_include_file' do
    let(:ssh_config_data) do
      {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22'
      }
    end

    it 'returns false for non-existent backup' do
      expect(ssh_config_manager.restore_include_file('/non/existent/path')).to be false
    end

    it 'restores include file from backup' do
      ssh_config_manager.add_ssh_entry(ssh_config_data)
      backup_path = ssh_config_manager.backup_include_file

      # Modify original file
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)
      File.write(include_file_path, 'Modified content')

      # Restore from backup
      expect(ssh_config_manager.restore_include_file(backup_path)).to be true

      # Check content is restored
      content = File.read(include_file_path)
      expect(content).to include('Host test-host')

      # Clean up backup
      File.delete(backup_path)
    end
  end

  describe '#validate_include_file' do
    it 'validates non-existent file as valid' do
      result = ssh_config_manager.validate_include_file
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it 'validates properly formatted include file' do
      ssh_data = {
        'Host' => 'test-host',
        'HostName' => '192.168.33.10',
        'Port' => '22',
        'User' => 'vagrant'
      }
      ssh_config_manager.add_ssh_entry(ssh_data)

      result = ssh_config_manager.validate_include_file
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it 'detects validation errors in malformed file' do
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)

      # Create malformed SSH config
      malformed_content = <<~SSH_CONFIG
        Host#{' '}
        HostName 192.168.33.10
        InvalidOption

        Port 22
      SSH_CONFIG

      File.write(include_file_path, malformed_content)

      result = ssh_config_manager.validate_include_file
      expect(result[:valid]).to be false
      expect(result[:errors]).not_to be_empty
      expect(result[:errors].first).to include('Empty host name')
    end

    it 'detects SSH options without host declaration' do
      include_file_path = ssh_config_manager.instance_variable_get(:@include_file_path)

      content = <<~SSH_CONFIG
        HostName 192.168.33.10
        Port 22
      SSH_CONFIG

      File.write(include_file_path, content)

      result = ssh_config_manager.validate_include_file
      expect(result[:valid]).to be false
      expect(result[:errors].any? { |e| e.include?('without host declaration') }).to be true
    end
  end

  describe 'error handling and edge cases' do
    it 'handles directory creation when auto_create_dir is disabled' do
      config.auto_create_dir = false
      FileUtils.rm_rf(config.ssh_config_dir)

      ssh_data = { 'Host' => 'test', 'HostName' => '192.168.1.1' }
      expect(ssh_config_manager.add_ssh_entry(ssh_data)).to be false
    end

    it 'handles concurrent access scenarios' do
      ssh_data = { 'Host' => 'test', 'HostName' => '192.168.1.1' }

      # Simulate concurrent writes
      threads = []
      5.times do |i|
        threads << Thread.new do
          data = ssh_data.merge('Host' => "test-#{i}")
          ssh_config_manager.add_ssh_entry(data)
        end
      end

      threads.each(&:join)

      entries = ssh_config_manager.project_ssh_entries
      expect(entries.length).to eq(5)
    end
  end

  describe 'project isolation' do
    it 'generates different project names for different paths' do
      machine1 = VagrantPlugins::SshConfigManager::MockMachineForSshConfigManager.new('web', '/path1')
      machine2 = VagrantPlugins::SshConfigManager::MockMachineForSshConfigManager.new('web', '/path2')

      manager1 = described_class.new(machine1, config)
      manager2 = described_class.new(machine2, config)

      expect(manager1.project_name).not_to eq(manager2.project_name)
    end

    it 'generates consistent project names for same path' do
      manager1 = described_class.new(machine, config)
      manager2 = described_class.new(machine, config)

      expect(manager1.project_name).to eq(manager2.project_name)
    end
  end
end
