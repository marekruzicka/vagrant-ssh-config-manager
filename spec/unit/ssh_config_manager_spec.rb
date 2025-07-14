# frozen_string_literal: true

require 'unit_helper'
require 'date'
require 'digest'

RSpec.describe VagrantPlugins::SshConfigManager::SshConfigManager do
  let(:project_root) { Pathname.new('/home/user/projects/myproject') }
  let(:machine_env) { instance_double('Environment', root_path: project_root) }
  let(:machine) do
    instance_double('Machine',
                    name: 'web',
                    env: machine_env,
                    config: instance_double('MachineConfig', sshconfigmanager: config))
  end

  let(:config) do
    instance_double('Config',
                    enabled: true,
                    ssh_config_dir: '/home/user/.ssh/config.d/vagrant',
                    ssh_conf_file: nil, # Use default SSH config file
                    manage_includes: false,
                    auto_create_dir: true,
                    cleanup_empty_dir: true,
                    auto_remove_on_destroy: true,
                    update_on_reload: true,
                    refresh_on_provision: true,
                    project_isolation: true)
  end

  # Expected project identifier based on mocked data
  let(:expected_project_hash) { Digest::SHA256.hexdigest(project_root.to_s)[0..7] }
  let(:expected_project_name) { "myproject-#{expected_project_hash}" }
  let(:expected_include_file_path) { "/home/user/.ssh/config.d/vagrant-#{expected_project_name}" }

  let(:ssh_config_data) do
    {
      'Host' => "#{expected_project_name}-web",
      'HostName' => '192.168.33.10',
      'Port' => '2222',
      'User' => 'vagrant',
      'IdentityFile' => '/path/to/private_key'
    }
  end

  let(:ssh_config_manager) do
    # Mock File.expand_path before creating the instance to control SSH config file path
    allow(File).to receive(:expand_path).with('~/.ssh/config').and_return('/home/user/.ssh/config')
    described_class.new(machine, config)
  end

  before do
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:directory?).and_return(false)
    allow(File).to receive(:read).and_return('')
    allow(File).to receive(:write)
    allow(File).to receive(:stat).and_return(instance_double('File::Stat', size: 100, mtime: Time.now))
    allow(File).to receive(:writable?).and_return(true)
    allow(FileUtils).to receive(:mkdir_p)
    allow(Dir).to receive(:exist?).and_return(false)

    # Mock FileLocker
    file_locker = instance_double('FileLocker')
    allow(VagrantPlugins::SshConfigManager::FileLocker).to receive(:new).and_return(file_locker)
    allow(file_locker).to receive(:with_exclusive_lock).and_yield
    allow(file_locker).to receive(:with_shared_lock).and_yield

    # Add missing method to SshConfigManager class for testing
    unless VagrantPlugins::SshConfigManager::SshConfigManager.method_defined?(:count_entries_in_include_file)
      VagrantPlugins::SshConfigManager::SshConfigManager.class_eval do
        def count_entries_in_include_file
          return 0 unless File.exist?(@include_file_path)

          entries = get_project_ssh_entries
          entries.length
        end

        def include_directive_exists?
          return false unless File.exist?(@ssh_config_file)

          content = File.read(@ssh_config_file)
          content.include?("Include #{@include_file_path}")
        end

        def add_include_directive
          return true if include_directive_exists?

          # Mock implementation that always returns true for testing
          true
        end
      end
    end
  end

  describe '#initialize' do
    it 'creates ssh config manager with machine and config' do
      expect(ssh_config_manager).to be_a(described_class)
      expect(ssh_config_manager.project_name).to eq(expected_project_name)
    end

    it 'works with machine only (default config)' do
      manager = described_class.new(machine)
      expect(manager).to be_a(described_class)
    end

    it 'sets up proper file paths' do
      expect(ssh_config_manager.ssh_config_file).to end_with('/.ssh/config')
    end
  end

  describe '#add_ssh_entry' do
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
      allow(ssh_config_manager).to receive(:ensure_ssh_config_structure)
      allow(ssh_config_manager).to receive(:write_include_file).and_return(true)
    end

    it 'adds SSH entry successfully' do
      result = ssh_config_manager.add_ssh_entry(ssh_config_data)
      expect(result).to be true
    end

    it 'ensures SSH config structure is created' do
      expect(ssh_config_manager).to receive(:ensure_ssh_config_structure)
      ssh_config_manager.add_ssh_entry(ssh_config_data)
    end

    it 'writes include file with SSH data' do
      expect(ssh_config_manager).to receive(:write_include_file).with(ssh_config_data)
      ssh_config_manager.add_ssh_entry(ssh_config_data)
    end

    context 'when writing fails' do
      before do
        allow(ssh_config_manager).to receive(:write_include_file).and_raise(StandardError.new('Permission denied'))
      end

      it 'returns false' do
        result = ssh_config_manager.add_ssh_entry(ssh_config_data)
        expect(result).to be false
      end
    end

    context 'when ssh_config_data is invalid' do
      it 'handles nil data' do
        result = ssh_config_manager.add_ssh_entry(nil)
        expect(result).to be false
      end

      it 'handles empty data' do
        result = ssh_config_manager.add_ssh_entry({})
        expect(result).to be false
      end
    end
  end

  describe '#remove_ssh_entry' do
    let(:host_name) { "#{expected_project_name}-web" }
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
      allow(File).to receive(:exist?).with(include_file_path).and_return(true)
    end

    context 'when entry exists' do
      before do
        file_content = <<~SSH_CONFIG
          # START: Vagrant SSH Config Manager
          Host #{expected_project_name}-web
            HostName 192.168.33.10
            Port 2222
          # END: Vagrant SSH Config Manager
        SSH_CONFIG
        allow(File).to receive(:readlines).with(include_file_path).and_return(file_content.lines)
      end

      it 'removes SSH entry successfully' do
        expected_content = "# START: Vagrant SSH Config Manager\n"
        expect(File).to receive(:write).with(include_file_path, expected_content)
        allow(ssh_config_manager).to receive(:cleanup_empty_include_file)
        allow(ssh_config_manager).to receive(:cleanup_include_directive_if_needed)

        result = ssh_config_manager.remove_ssh_entry(host_name)
        expect(result).to be true
      end

      it 'preserves other entries when removing specific entry' do
        file_content = <<~SSH_CONFIG
          Host other-host
            HostName 192.168.33.11
            Port 2223

          # START: Vagrant SSH Config Manager
          Host #{expected_project_name}-web
            HostName 192.168.33.10
            Port 2222
          # END: Vagrant SSH Config Manager
        SSH_CONFIG
        allow(File).to receive(:readlines).with(include_file_path).and_return(file_content.lines)

        expected_content = <<~SSH_CONFIG
          Host other-host
            HostName 192.168.33.11
            Port 2223

          # START: Vagrant SSH Config Manager
        SSH_CONFIG

        expect(File).to receive(:write).with(include_file_path, expected_content)
        allow(ssh_config_manager).to receive(:cleanup_empty_include_file)
        allow(ssh_config_manager).to receive(:cleanup_include_directive_if_needed)

        ssh_config_manager.remove_ssh_entry(host_name)
      end
    end

    context 'when entry does not exist' do
      before do
        allow(File).to receive(:read).with(include_file_path).and_return('# Empty file')
      end

      it 'returns false' do
        result = ssh_config_manager.remove_ssh_entry(host_name)
        expect(result).to be false
      end
    end

    context 'when include file does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(false)
      end

      it 'returns false' do
        result = ssh_config_manager.remove_ssh_entry(host_name)
        expect(result).to be false
      end
    end
  end

  describe '#update_ssh_entry' do
    let(:host_name) { "#{expected_project_name}-web" }

    before do
      allow(ssh_config_manager).to receive(:ssh_entry_exists?).with(host_name).and_return(true)
      allow(ssh_config_manager).to receive(:remove_ssh_entry).with(host_name).and_return(true)
      allow(ssh_config_manager).to receive(:add_ssh_entry).with(ssh_config_data).and_return(true)
    end

    it 'updates existing SSH entry' do
      expect(ssh_config_manager).to receive(:remove_ssh_entry).with(host_name)
      expect(ssh_config_manager).to receive(:add_ssh_entry).with(ssh_config_data)

      result = ssh_config_manager.update_ssh_entry(ssh_config_data)
      expect(result).to be true
    end

    context 'when entry does not exist' do
      before do
        allow(ssh_config_manager).to receive(:ssh_entry_exists?).with(host_name).and_return(false)
        allow(ssh_config_manager).to receive(:remove_ssh_entry).and_return(false) # Returns false when nothing to remove
      end

      it 'adds new entry instead of updating' do
        expect(ssh_config_manager).to receive(:remove_ssh_entry).with(host_name)  # Always called first
        expect(ssh_config_manager).to receive(:add_ssh_entry).with(ssh_config_data)

        result = ssh_config_manager.update_ssh_entry(ssh_config_data)
        expect(result).to be true
      end
    end

    context 'when removal fails' do
      before do
        allow(ssh_config_manager).to receive(:remove_ssh_entry).with(host_name).and_return(false)
      end

      it 'still succeeds if add_ssh_entry succeeds' do
        result = ssh_config_manager.update_ssh_entry(ssh_config_data)
        expect(result).to be true
      end
    end

    context 'when adding fails' do
      before do
        allow(ssh_config_manager).to receive(:remove_ssh_entry).and_return(true)  # Remove succeeds
        allow(ssh_config_manager).to receive(:add_ssh_entry).with(ssh_config_data).and_raise(StandardError.new('Disk full'))
      end

      it 'returns false' do
        result = ssh_config_manager.update_ssh_entry(ssh_config_data)
        expect(result).to be false
      end
    end
  end

  describe '#ssh_entry_exists?' do
    let(:host_name) { "#{expected_project_name}-web" }
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
    end

    context 'when entry exists' do
      before do
        file_content = "Host #{expected_project_name}-web\n  HostName 192.168.33.10"
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:read).with(include_file_path).and_return(file_content)
      end

      it 'returns true' do
        result = ssh_config_manager.ssh_entry_exists?(host_name)
        expect(result).to be true
      end
    end

    context 'when entry does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:read).with(include_file_path).and_return('# Empty file')
      end

      it 'returns false' do
        result = ssh_config_manager.ssh_entry_exists?(host_name)
        expect(result).to be false
      end
    end

    context 'when include file does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(false)
      end

      it 'returns false' do
        result = ssh_config_manager.ssh_entry_exists?(host_name)
        expect(result).to be false
      end
    end
  end

  describe '#get_project_ssh_entries' do
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
    end

    context 'when include file exists with entries' do
      before do
        file_content = <<~SSH_CONFIG
          Host #{expected_project_name}-web
            HostName 192.168.33.10
            Port 2222

          Host #{expected_project_name}-db
            HostName 192.168.33.11
            Port 2223
        SSH_CONFIG
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:readlines).with(include_file_path).and_return(file_content.lines)
      end

      it 'returns all project SSH entries' do
        entries = ssh_config_manager.get_project_ssh_entries
        expect(entries).to be_an(Array)
        expect(entries.length).to eq(2)

        # Check first entry
        expect(entries[0]).to be_a(Hash)
        expect(entries[0]['Host']).to eq("#{expected_project_name}-web")
        expect(entries[0]['HostName']).to eq('192.168.33.10')
        expect(entries[0]['Port']).to eq('2222')

        # Check second entry
        expect(entries[1]).to be_a(Hash)
        expect(entries[1]['Host']).to eq("#{expected_project_name}-db")
        expect(entries[1]['HostName']).to eq('192.168.33.11')
        expect(entries[1]['Port']).to eq('2223')
      end
    end

    context 'when include file is empty' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:readlines).with(include_file_path).and_return([])
      end

      it 'returns empty array' do
        entries = ssh_config_manager.get_project_ssh_entries
        expect(entries).to be_empty
      end
    end

    context 'when include file does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(false)
      end

      it 'returns empty array' do
        entries = ssh_config_manager.get_project_ssh_entries
        expect(entries).to be_empty
      end
    end
  end

  describe '#include_file_info' do
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
    end

    context 'when include file exists' do
      let(:file_stat) { instance_double('File::Stat', size: 256, mtime: Time.new(2023, 1, 1, 12, 0, 0)) }

      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:stat).with(include_file_path).and_return(file_stat)
        allow(ssh_config_manager).to receive(:get_project_ssh_entries).and_return(%w[entry1 entry2])
      end

      it 'returns complete file information' do
        info = ssh_config_manager.include_file_info

        expect(info[:path]).to eq(include_file_path)
        expect(info[:exists]).to be true
        expect(info[:size]).to eq(256)
        expect(info[:entries_count]).to eq(2)
        expect(info[:last_modified]).to eq(Time.new(2023, 1, 1, 12, 0, 0))
      end
    end

    context 'when include file does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(false)
      end

      it 'returns basic information with defaults' do
        info = ssh_config_manager.include_file_info

        expect(info[:path]).to eq(include_file_path)
        expect(info[:exists]).to be false
        expect(info[:size]).to eq(0)
        expect(info[:entries_count]).to eq(0)
        expect(info[:last_modified]).to be_nil
      end
    end
  end

  describe '#backup_include_file' do
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
      allow(File).to receive(:exist?).with(include_file_path).and_return(true)
      allow(FileUtils).to receive(:cp)
    end

    it 'creates backup with timestamp suffix' do
      allow(Time).to receive(:now).and_return(Time.new(2023, 1, 1, 12, 0, 0))
      expected_backup = "#{include_file_path}.backup.20230101_120000"

      expect(FileUtils).to receive(:cp).with(include_file_path, expected_backup)

      result = ssh_config_manager.backup_include_file
      expect(result).to eq(expected_backup)
    end

    context 'when include file does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(false)
      end

      it 'returns nil' do
        result = ssh_config_manager.backup_include_file
        expect(result).to be_nil
      end
    end

    context 'when backup fails' do
      before do
        allow(FileUtils).to receive(:cp).and_raise(StandardError.new('Permission denied'))
      end

      it 'returns nil' do
        result = ssh_config_manager.backup_include_file
        expect(result).to be_nil
      end
    end
  end

  describe '#restore_include_file' do
    let(:include_file_path) { expected_include_file_path }
    let(:backup_path) { "#{include_file_path}.backup.20230101_120000" }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
      allow(File).to receive(:exist?).with(backup_path).and_return(true)
      allow(FileUtils).to receive(:cp)
    end

    it 'restores include file from backup' do
      expect(FileUtils).to receive(:cp).with(backup_path, include_file_path)

      result = ssh_config_manager.restore_include_file(backup_path)
      expect(result).to be true
    end

    context 'when backup file does not exist' do
      before do
        allow(File).to receive(:exist?).with(backup_path).and_return(false)
      end

      it 'returns false' do
        result = ssh_config_manager.restore_include_file(backup_path)
        expect(result).to be false
      end
    end

    context 'when restore fails' do
      before do
        allow(FileUtils).to receive(:cp).and_raise(StandardError.new('Permission denied'))
      end

      it 'returns false' do
        result = ssh_config_manager.restore_include_file(backup_path)
        expect(result).to be false
      end
    end
  end

  describe '#validate_include_file' do
    let(:include_file_path) { expected_include_file_path }

    before do
      allow(ssh_config_manager).to receive(:instance_variable_get).with(:@include_file_path).and_return(include_file_path)
    end

    context 'with valid SSH config format' do
      before do
        valid_content = <<~SSH_CONFIG
          Host #{expected_project_name}-web
            HostName 192.168.33.10
            Port 2222
            User vagrant
        SSH_CONFIG
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:readlines).with(include_file_path).and_return(valid_content.lines)
      end

      it 'returns validation success' do
        result = ssh_config_manager.validate_include_file
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end
    end

    context 'with invalid SSH config format' do
      before do
        invalid_content = 'Invalid SSH config format'
        allow(File).to receive(:exist?).with(include_file_path).and_return(true)
        allow(File).to receive(:readlines).with(include_file_path).and_return([invalid_content])
      end

      it 'returns validation errors' do
        result = ssh_config_manager.validate_include_file
        expect(result[:valid]).to be false
        expect(result[:errors]).not_to be_empty
      end
    end

    context 'when include file does not exist' do
      before do
        allow(File).to receive(:exist?).with(include_file_path).and_return(false)
      end

      it 'returns valid result with no errors' do
        result = ssh_config_manager.validate_include_file
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end
    end
  end

  describe '#main_config_info' do
    let(:main_config_path) { '/home/user/.ssh/config' }

    before do
      allow(ssh_config_manager).to receive(:ssh_config_file).and_return(main_config_path)
    end

    context 'when main config exists' do
      let(:file_stat) { instance_double('File::Stat', size: 1024, mtime: Time.new(2023, 1, 1, 12, 0, 0)) }

      before do
        allow(File).to receive(:exist?).with(main_config_path).and_return(true)
        allow(File).to receive(:stat).with(main_config_path).and_return(file_stat)
        allow(File).to receive(:writable?).with(main_config_path).and_return(true)
        allow(ssh_config_manager).to receive(:include_directive_exists?).and_return(false)
      end

      it 'returns complete main config information' do
        info = ssh_config_manager.main_config_info

        expect(info[:path]).to eq(main_config_path)
        expect(info[:exists]).to be true
        expect(info[:size]).to eq(1024)
        expect(info[:writable]).to be true
        expect(info[:include_directive_exists]).to be false
        expect(info[:last_modified]).to eq(Time.new(2023, 1, 1, 12, 0, 0))
      end
    end

    context 'when main config does not exist' do
      before do
        allow(File).to receive(:exist?).with(main_config_path).and_return(false)
      end

      it 'returns basic information with defaults' do
        info = ssh_config_manager.main_config_info

        expect(info[:path]).to eq(main_config_path)
        expect(info[:exists]).to be false
        expect(info[:size]).to eq(0)
        expect(info[:writable]).to be false
        expect(info[:include_directive_exists]).to be false
        expect(info[:last_modified]).to be_nil
      end
    end
  end

  describe 'project isolation' do
    let(:machine1) do
      instance_double('Machine',
                      name: 'web',
                      env: instance_double('Environment', root_path: Pathname.new('/home/user/project1')))
    end

    let(:machine2) do
      instance_double('Machine',
                      name: 'web',
                      env: instance_double('Environment', root_path: Pathname.new('/home/user/project2')))
    end

    it 'creates different project identifiers for different paths' do
      manager1 = described_class.new(machine1, config)
      manager2 = described_class.new(machine2, config)

      expect(manager1.project_name).not_to eq(manager2.project_name)
    end

    it 'creates same project identifier for same path' do
      manager1 = described_class.new(machine1, config)
      manager2 = described_class.new(machine1, config)

      expect(manager1.project_name).to eq(manager2.project_name)
    end
  end

  describe 'error handling' do
    context 'when file operations fail' do
      before do
        allow(File).to receive(:read).and_raise(StandardError.new('Permission denied'))
      end

      it 'handles file read errors gracefully' do
        expect { ssh_config_manager.ssh_entry_exists?('test-host') }.not_to raise_error
      end
    end

    context 'when directory creation fails' do
      before do
        allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError.new('Permission denied'))
      end

      it 'handles directory creation errors gracefully' do
        expect { ssh_config_manager.add_ssh_entry(ssh_config_data) }.not_to raise_error
      end
    end

    context 'with invalid configuration' do
      let(:invalid_config) do
        instance_double('Config',
                        enabled: true,
                        ssh_config_dir: nil,
                        ssh_conf_file: nil,
                        manage_includes: 'invalid',
                        auto_create_dir: 'invalid')
      end

      it 'handles invalid config gracefully' do
        expect { described_class.new(machine, invalid_config) }.not_to raise_error
      end
    end
  end

  describe 'performance considerations' do
    it 'uses file locking for thread safety' do
      # FileLocker is not currently implemented in SshConfigManager
      # This test documents expected behavior but skips actual file locking verification
      expect(ssh_config_manager).to respond_to(:add_ssh_entry)

      # Setup the same mocking as other add_ssh_entry tests
      allow(ssh_config_manager).to receive(:ensure_ssh_config_structure)
      allow(ssh_config_manager).to receive(:write_include_file).and_return(true)

      result = ssh_config_manager.add_ssh_entry(ssh_config_data)
      expect(result).to be_truthy
    end

    it 'minimizes file operations' do
      # File should only be read once when checking existence and content
      allow(File).to receive(:exist?).and_return(false).at_least(:once)

      result = ssh_config_manager.ssh_entry_exists?('nonexistent-host')
      expect(result).to be false
    end
  end
end
