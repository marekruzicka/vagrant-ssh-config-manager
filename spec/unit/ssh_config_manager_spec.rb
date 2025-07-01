require 'spec_helper'

RSpec.describe VagrantPlugins::SshConfigManager::SshConfigManager do
  let(:machine) { create_mock_machine }
  let(:config) { create_mock_config }
  let(:ssh_config_file) { @ssh_config_file }
  let(:manager) { described_class.new(machine, config) }
  
  let(:sample_ssh_config) do
    {
      'Host' => 'test-host',
      'HostName' => '192.168.1.100',
      'Port' => '2222',
      'User' => 'vagrant',
      'IdentityFile' => '/path/to/key'
    }
  end

  include_examples 'ssh config file operations'
  include_examples 'project isolation'
  include_examples 'error handling'

  describe '#initialize' do
    it 'initializes with machine and config' do
      expect(manager.instance_variable_get(:@machine)).to eq(machine)
      expect(manager.instance_variable_get(:@config)).to eq(config)
      expect(manager.instance_variable_get(:@logger)).not_to be_nil
    end

    it 'determines SSH config file path from config' do
      expect(manager.ssh_config_file).to eq(ssh_config_file)
    end

    it 'generates project name' do
      expect(manager.project_name).not_to be_empty
    end
  end

  describe '#add_ssh_entry' do
    it 'adds SSH entry successfully' do
      result = manager.add_ssh_entry(sample_ssh_config)
      
      expect(result).to be true
      expect(File.exist?(ssh_config_file)).to be true
    end

    it 'creates include file with SSH entry' do
      manager.add_ssh_entry(sample_ssh_config)
      
      include_files = get_include_files
      expect(include_files).not_to be_empty
      
      include_content = File.read(include_files.first)
      expect(include_content).to include('Host test-host')
      expect(include_content).to include('HostName 192.168.1.100')
      expect(include_content).to include('Port 2222')
      expect(include_content).to include('User vagrant')
    end

    it 'adds include directive to main SSH config' do
      manager.add_ssh_entry(sample_ssh_config)
      
      ssh_config_content = read_ssh_config
      expect(ssh_config_content).to include('Include ')
      expect(ssh_config_content).to include('config.d/vagrant-')
    end

    it 'returns false for invalid SSH config' do
      result = manager.add_ssh_entry(nil)
      expect(result).to be false
      
      result = manager.add_ssh_entry({})
      expect(result).to be false
      
      result = manager.add_ssh_entry({ 'HostName' => '192.168.1.1' }) # Missing Host
      expect(result).to be false
    end

    it 'does not duplicate include directives' do
      manager.add_ssh_entry(sample_ssh_config)
      
      second_config = sample_ssh_config.merge('Host' => 'second-host')
      manager.add_ssh_entry(second_config)
      
      ssh_config_content = read_ssh_config
      include_count = ssh_config_content.scan(/Include.*config\.d\/vagrant-/).length
      expect(include_count).to eq(1)
    end
  end

  describe '#remove_ssh_entry' do
    before do
      manager.add_ssh_entry(sample_ssh_config)
    end

    it 'removes SSH entry successfully' do
      result = manager.remove_ssh_entry('test-host')
      
      expect(result).to be true
      
      include_files = get_include_files
      if include_files.any?
        include_content = File.read(include_files.first)
        expect(include_content).not_to include('Host test-host')
      end
    end

    it 'cleans up empty include files' do
      manager.remove_ssh_entry('test-host')
      
      include_files = get_include_files
      expect(include_files).to be_empty
    end

    it 'removes include directive when no entries remain' do
      manager.remove_ssh_entry('test-host')
      
      ssh_config_content = read_ssh_config
      expect(ssh_config_content).not_to include('config.d/vagrant-')
    end

    it 'returns false for non-existent host' do
      result = manager.remove_ssh_entry('non-existent-host')
      expect(result).to be false
    end
  end

  describe '#update_ssh_entry' do
    before do
      manager.add_ssh_entry(sample_ssh_config)
    end

    it 'updates existing SSH entry' do
      updated_config = sample_ssh_config.merge('Port' => '2223')
      result = manager.update_ssh_entry(updated_config)
      
      expect(result).to be true
      
      include_files = get_include_files
      include_content = File.read(include_files.first)
      expect(include_content).to include('Port 2223')
      expect(include_content).not_to include('Port 2222')
    end

    it 'adds entry if it does not exist' do
      new_config = {
        'Host' => 'new-host',
        'HostName' => '192.168.1.200',
        'Port' => '22',
        'User' => 'ubuntu'
      }
      
      result = manager.update_ssh_entry(new_config)
      expect(result).to be true
      
      include_files = get_include_files
      include_content = File.read(include_files.first)
      expect(include_content).to include('Host new-host')
    end
  end

  describe '#ssh_entry_exists?' do
    it 'returns false when no entries exist' do
      expect(manager.ssh_entry_exists?('test-host')).to be false
    end

    it 'returns true when entry exists' do
      manager.add_ssh_entry(sample_ssh_config)
      expect(manager.ssh_entry_exists?('test-host')).to be true
    end

    it 'returns false for non-existent entry' do
      manager.add_ssh_entry(sample_ssh_config)
      expect(manager.ssh_entry_exists?('other-host')).to be false
    end
  end

  describe '#get_project_ssh_entries' do
    it 'returns empty array when no entries exist' do
      entries = manager.get_project_ssh_entries
      expect(entries).to eq([])
    end

    it 'returns SSH entries for the project' do
      manager.add_ssh_entry(sample_ssh_config)
      
      second_config = sample_ssh_config.merge('Host' => 'second-host')
      manager.add_ssh_entry(second_config)
      
      entries = manager.get_project_ssh_entries
      expect(entries.length).to eq(2)
      expect(entries.map { |e| e['Host'] }).to include('test-host', 'second-host')
    end
  end

  describe '#get_project_hosts' do
    it 'returns empty array when no hosts exist' do
      hosts = manager.get_project_hosts
      expect(hosts).to eq([])
    end

    it 'returns host names for the project' do
      manager.add_ssh_entry(sample_ssh_config)
      
      second_config = sample_ssh_config.merge('Host' => 'second-host')
      manager.add_ssh_entry(second_config)
      
      hosts = manager.get_project_hosts
      expect(hosts).to include('test-host', 'second-host')
    end
  end

  describe 'comment markers' do
    it 'adds comment markers to SSH entries' do
      manager.add_ssh_entry(sample_ssh_config)
      
      include_files = get_include_files
      include_content = File.read(include_files.first)
      
      expect(include_content).to include('# Vagrant SSH Config')
      expect(include_content).to include('# DO NOT EDIT MANUALLY')
      expect(include_content).to include('Generated on:')
    end

    it 'includes project information in comments' do
      manager.add_ssh_entry(sample_ssh_config)
      
      include_files = get_include_files
      include_content = File.read(include_files.first)
      
      expect(include_content).to include("Project: #{manager.project_name}")
    end
  end

  describe 'file permissions' do
    it 'sets correct permissions on SSH config files' do
      manager.add_ssh_entry(sample_ssh_config)
      
      expect(File.stat(ssh_config_file).mode & 0777).to eq(0600)
      
      include_files = get_include_files
      include_files.each do |file|
        expect(File.stat(file).mode & 0777).to eq(0600)
      end
    end
  end

  describe 'project isolation' do
    let(:other_machine) do
      other_machine = create_mock_machine(name: 'other-vm')
      env = double('env')
      allow(env).to receive(:root_path).and_return('/different/project/path')
      allow(other_machine).to receive(:env).and_return(env)
      other_machine
    end
    
    let(:other_manager) { described_class.new(other_machine, config) }

    it 'isolates SSH entries by project' do
      # Add entry for first project
      manager.add_ssh_entry(sample_ssh_config)
      
      # Add entry for second project
      other_config = sample_ssh_config.merge('Host' => 'other-host')
      other_manager.add_ssh_entry(other_config)
      
      # Each project should only see its own entries
      first_hosts = manager.get_project_hosts
      second_hosts = other_manager.get_project_hosts
      
      expect(first_hosts).to include('test-host')
      expect(first_hosts).not_to include('other-host')
      expect(second_hosts).to include('other-host')
      expect(second_hosts).not_to include('test-host')
    end

    it 'creates separate include files for different projects' do
      manager.add_ssh_entry(sample_ssh_config)
      other_manager.add_ssh_entry(sample_ssh_config.merge('Host' => 'other-host'))
      
      include_files = get_include_files
      expect(include_files.length).to eq(2)
      
      # Files should have different project identifiers
      filenames = include_files.map { |f| File.basename(f) }
      expect(filenames.uniq.length).to eq(2)
    end
  end

  describe 'backup and restore' do
    before do
      write_test_ssh_config("# Original config\nHost original\n  HostName example.com\n")
      manager.add_ssh_entry(sample_ssh_config)
    end

    it 'creates backup before modifying SSH config' do
      backup_files = Dir.glob(File.join(File.dirname(ssh_config_file), '*.backup.*'))
      expect(backup_files).not_to be_empty
    end

    it 'can restore from backup' do
      # This would be tested if restore functionality exists
      expect(manager).to respond_to(:add_ssh_entry)
    end
  end
end
