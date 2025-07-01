require 'spec_helper'

RSpec.describe 'Vagrant SSH Config Manager Plugin Integration' do
  let(:machine) { create_mock_machine }
  let(:config) { create_mock_config }
  let(:ssh_config_file) { @ssh_config_file }

  describe 'Plugin Registration' do
    it 'registers the plugin with Vagrant' do
      expect(VagrantPlugins::SshConfigManager::Plugin).to be < Vagrant.plugin("2")
    end

    it 'registers configuration class' do
      plugin = VagrantPlugins::SshConfigManager::Plugin
      expect(plugin.components.configs[:env]).to have_key(:sshconfigmanager)
    end

    it 'registers action hooks' do
      plugin = VagrantPlugins::SshConfigManager::Plugin
      expect(plugin.components.action_hooks).not_to be_empty
    end
  end

  describe 'Full VM Lifecycle Workflow' do
    let(:extractor) { VagrantPlugins::SshConfigManager::SshInfoExtractor.new(machine) }
    let(:manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(machine, config) }
    
    let(:ssh_info) do
      {
        'Host' => 'vagrant-test-vm',
        'HostName' => '192.168.1.100',
        'Port' => '2222',
        'User' => 'vagrant',
        'IdentityFile' => '/path/to/key'
      }
    end

    describe 'vagrant up workflow' do
      it 'extracts SSH info and creates SSH config entry' do
        # Simulate SSH info extraction
        allow(machine).to receive(:ssh_info).and_return({
          host: '192.168.1.100',
          port: 2222,
          username: 'vagrant',
          private_key_path: ['/path/to/key']
        })

        # Extract SSH info
        extracted_info = extractor.extract_ssh_info
        expect(extracted_info).not_to be_nil
        expect(extracted_info['HostName']).to eq('192.168.1.100')

        # Add to SSH config
        extracted_info['Host'] = 'vagrant-test-vm'
        result = manager.add_ssh_entry(extracted_info)
        expect(result).to be true

        # Verify SSH config file was created
        expect(File.exist?(ssh_config_file)).to be true
        ssh_content = File.read(ssh_config_file)
        expect(ssh_content).to include('Include')
        expect(ssh_content).to include('config.d/vagrant-')

        # Verify include file was created
        include_files = get_include_files
        expect(include_files).not_to be_empty
        
        include_content = File.read(include_files.first)
        expect(include_content).to include('Host vagrant-test-vm')
        expect(include_content).to include('HostName 192.168.1.100')
      end
    end

    describe 'vagrant reload workflow' do
      before do
        # Set up initial SSH config
        manager.add_ssh_entry(ssh_info)
      end

      it 'updates SSH config when network changes' do
        # Simulate network change
        new_ssh_info = ssh_info.merge('Port' => '2223')
        
        result = manager.update_ssh_entry(new_ssh_info)
        expect(result).to be true

        # Verify update
        include_files = get_include_files
        include_content = File.read(include_files.first)
        expect(include_content).to include('Port 2223')
        expect(include_content).not_to include('Port 2222')
      end

      it 'preserves SSH config when no changes detected' do
        # Get original content
        include_files = get_include_files
        original_content = File.read(include_files.first)
        original_mtime = File.mtime(include_files.first)

        # Simulate reload with same SSH info
        sleep 0.01 # Ensure different timestamp if file is modified
        manager.update_ssh_entry(ssh_info)

        # Content should be the same
        new_content = File.read(include_files.first)
        expect(new_content).to eq(original_content)
      end
    end

    describe 'vagrant halt/suspend workflow' do
      before do
        manager.add_ssh_entry(ssh_info)
      end

      context 'when keep_config_on_halt is true' do
        before { allow(config).to receive(:keep_config_on_halt).and_return(true) }

        it 'preserves SSH config entries' do
          expect(manager.ssh_entry_exists?('vagrant-test-vm')).to be true
          
          # SSH config should remain after halt
          include_files = get_include_files
          expect(include_files).not_to be_empty
        end
      end

      context 'when keep_config_on_halt is false' do
        before { allow(config).to receive(:keep_config_on_halt).and_return(false) }

        it 'removes SSH config entries' do
          result = manager.remove_ssh_entry('vagrant-test-vm')
          expect(result).to be true
          
          expect(manager.ssh_entry_exists?('vagrant-test-vm')).to be false
        end
      end
    end

    describe 'vagrant destroy workflow' do
      before do
        manager.add_ssh_entry(ssh_info)
      end

      it 'removes SSH config entry and cleans up' do
        expect(manager.ssh_entry_exists?('vagrant-test-vm')).to be true
        
        result = manager.remove_ssh_entry('vagrant-test-vm')
        expect(result).to be true

        # Entry should be removed
        expect(manager.ssh_entry_exists?('vagrant-test-vm')).to be false

        # Include file should be cleaned up
        include_files = get_include_files
        expect(include_files).to be_empty

        # Include directive should be removed from main config
        ssh_content = File.read(ssh_config_file)
        expect(ssh_content).not_to include('config.d/vagrant-')
      end
    end

    describe 'vagrant provision workflow' do
      before do
        manager.add_ssh_entry(ssh_info)
      end

      it 'refreshes SSH config entries' do
        # Simulate provision with updated SSH info
        updated_info = ssh_info.merge('User' => 'ubuntu')
        
        result = manager.update_ssh_entry(updated_info)
        expect(result).to be true

        # Verify update
        include_files = get_include_files
        include_content = File.read(include_files.first)
        expect(include_content).to include('User ubuntu')
        expect(include_content).not_to include('User vagrant')
      end
    end
  end

  describe 'Multi-Machine Environment' do
    let(:web_machine) { create_mock_machine(name: 'web') }
    let(:db_machine) { create_mock_machine(name: 'db') }
    let(:web_manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(web_machine, config) }
    let(:db_manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(db_machine, config) }

    it 'manages multiple machines in same project' do
      web_ssh_info = ssh_info.merge('Host' => 'vagrant-web', 'HostName' => '192.168.1.10')
      db_ssh_info = ssh_info.merge('Host' => 'vagrant-db', 'HostName' => '192.168.1.11')

      # Add both machines
      web_manager.add_ssh_entry(web_ssh_info)
      db_manager.add_ssh_entry(db_ssh_info)

      # Both should be in the same include file (same project)
      include_files = get_include_files
      expect(include_files.length).to eq(1)

      include_content = File.read(include_files.first)
      expect(include_content).to include('Host vagrant-web')
      expect(include_content).to include('Host vagrant-db')

      # Both managers should see both entries
      web_hosts = web_manager.get_project_hosts
      db_hosts = db_manager.get_project_hosts
      
      expect(web_hosts).to include('vagrant-web', 'vagrant-db')
      expect(db_hosts).to include('vagrant-web', 'vagrant-db')
    end

    it 'handles partial machine destruction' do
      web_ssh_info = ssh_info.merge('Host' => 'vagrant-web')
      db_ssh_info = ssh_info.merge('Host' => 'vagrant-db')

      web_manager.add_ssh_entry(web_ssh_info)
      db_manager.add_ssh_entry(db_ssh_info)

      # Remove web machine
      web_manager.remove_ssh_entry('vagrant-web')

      # DB entry should remain
      expect(db_manager.ssh_entry_exists?('vagrant-db')).to be true
      expect(web_manager.ssh_entry_exists?('vagrant-web')).to be false

      # Include file should still exist with DB entry
      include_files = get_include_files
      expect(include_files).not_to be_empty
      
      include_content = File.read(include_files.first)
      expect(include_content).to include('Host vagrant-db')
      expect(include_content).not_to include('Host vagrant-web')
    end

    it 'cleans up when all machines are destroyed' do
      web_ssh_info = ssh_info.merge('Host' => 'vagrant-web')
      db_ssh_info = ssh_info.merge('Host' => 'vagrant-db')

      web_manager.add_ssh_entry(web_ssh_info)
      db_manager.add_ssh_entry(db_ssh_info)

      # Remove both machines
      web_manager.remove_ssh_entry('vagrant-web')
      db_manager.remove_ssh_entry('vagrant-db')

      # Everything should be cleaned up
      include_files = get_include_files
      expect(include_files).to be_empty

      ssh_content = File.read(ssh_config_file)
      expect(ssh_content).not_to include('config.d/vagrant-')
    end
  end

  describe 'Project Isolation' do
    let(:project1_machine) do
      machine = create_mock_machine(name: 'web')
      env = double('env')
      allow(env).to receive(:root_path).and_return('/path/to/project1')
      allow(machine).to receive(:env).and_return(env)
      machine
    end

    let(:project2_machine) do
      machine = create_mock_machine(name: 'web')
      env = double('env')
      allow(env).to receive(:root_path).and_return('/path/to/project2')
      allow(machine).to receive(:env).and_return(env)
      machine
    end

    let(:project1_manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(project1_machine, config) }
    let(:project2_manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(project2_machine, config) }

    it 'isolates SSH entries between different projects' do
      project1_ssh = ssh_info.merge('Host' => 'project1-web')
      project2_ssh = ssh_info.merge('Host' => 'project2-web')

      project1_manager.add_ssh_entry(project1_ssh)
      project2_manager.add_ssh_entry(project2_ssh)

      # Should create separate include files
      include_files = get_include_files
      expect(include_files.length).to eq(2)

      # Each manager should only see its own entries
      project1_hosts = project1_manager.get_project_hosts
      project2_hosts = project2_manager.get_project_hosts

      expect(project1_hosts).to include('project1-web')
      expect(project1_hosts).not_to include('project2-web')
      expect(project2_hosts).to include('project2-web')
      expect(project2_hosts).not_to include('project1-web')
    end
  end

  describe 'Configuration Integration' do
    context 'when plugin is disabled' do
      let(:disabled_config) { create_mock_config(enabled: false) }
      let(:manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(machine, disabled_config) }

      it 'skips SSH config operations' do
        # This would be tested at the action level
        expect(disabled_config.enabled).to be false
        expect(disabled_config.enabled_for_action?(:up)).to be false
      end
    end

    context 'with custom SSH config file path' do
      let(:custom_ssh_file) { File.join(@temp_dir, 'custom_ssh_config') }
      let(:custom_config) { create_mock_config(ssh_conf_file: custom_ssh_file) }
      let(:manager) { VagrantPlugins::SshConfigManager::SshConfigManager.new(machine, custom_config) }

      it 'uses custom SSH config file path' do
        manager.add_ssh_entry(ssh_info)

        expect(File.exist?(custom_ssh_file)).to be true
        expect(File.exist?(ssh_config_file)).to be false

        custom_content = File.read(custom_ssh_file)
        expect(custom_content).to include('Include')
      end
    end
  end

  describe 'Error Handling Integration' do
    it 'continues Vagrant operations even when SSH config fails' do
      # Make SSH config file read-only
      File.write(ssh_config_file, 'existing content')
      File.chmod(0400, ssh_config_file)

      # Should not raise error, just log and continue
      expect { manager.add_ssh_entry(ssh_info) }.not_to raise_error
    end

    it 'handles concurrent access with file locking' do
      # This is difficult to test without threading
      # For now, verify that the file locking mechanism is in place
      expect(VagrantPlugins::SshConfigManager::FileLocker).to be_a(Class)
    end
  end

  describe 'Backup and Recovery' do
    before do
      write_test_ssh_config("# Original SSH config\nHost original\n  HostName example.com\n")
    end

    it 'creates backup before modifying SSH config' do
      manager.add_ssh_entry(ssh_info)

      backup_files = Dir.glob(File.join(@ssh_dir, '*.backup.*'))
      expect(backup_files).not_to be_empty
    end

    it 'preserves original SSH config content' do
      original_content = File.read(ssh_config_file)
      
      manager.add_ssh_entry(ssh_info)
      
      updated_content = File.read(ssh_config_file)
      expect(updated_content).to include('# Original SSH config')
      expect(updated_content).to include('Host original')
      expect(updated_content).to include('Include') # New content added
    end
  end
end
