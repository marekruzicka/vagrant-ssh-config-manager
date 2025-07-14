require 'unit_helper'

RSpec.describe VagrantPlugins::SshConfigManager::FileManager do
  let(:config) do
    instance_double('Config',
      enabled: true,
      ssh_config_dir: '/home/user/.ssh/config.d/vagrant',
      project_isolation: true,
      cleanup_empty_dir: true,
      manage_includes: false
    )
  end
  
  let(:machine) do
    instance_double('Machine',
      name: 'web',
      env: instance_double('Environment', root_path: Pathname.new('/home/user/project'))
    )
  end
  
  let(:ssh_info) do
    {
      host: '192.168.33.10',
      port: 2222,
      username: 'vagrant',
      private_key_path: ['/home/user/.vagrant/machines/web/virtualbox/private_key']
    }
  end
  
  let(:file_manager) { described_class.new(config) }
  
  before do
    allow(machine).to receive(:ssh_info).and_return(ssh_info)
    allow(FileUtils).to receive(:mkdir_p)
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:directory?).and_return(false)
    allow(Dir).to receive(:exist?).and_return(false)
    allow(Dir).to receive(:entries).and_return(['.', '..'])
  end

  describe '#initialize' do
    it 'creates file manager with config' do
      expect(file_manager).to be_a(described_class)
    end
  end

  describe '#generate_filename' do
    it 'generates filename with project hash and machine name' do
      filename = file_manager.generate_filename(machine)
      expect(filename).to match(/^[a-f0-9]{8}-web\.conf$/)
    end

    it 'uses consistent project hash for same path' do
      filename1 = file_manager.generate_filename(machine)
      filename2 = file_manager.generate_filename(machine)
      expect(filename1).to eq(filename2)
    end

    it 'generates different hashes for different projects' do
      machine2 = instance_double('Machine',
        name: 'web',
        env: instance_double('Environment', root_path: Pathname.new('/home/user/other-project'))
      )
      
      filename1 = file_manager.generate_filename(machine)
      filename2 = file_manager.generate_filename(machine2)
      expect(filename1).not_to eq(filename2)
    end
  end

  describe '#file_path' do
    it 'returns full path combining config dir and filename' do
      path = file_manager.file_path(machine)
      expect(path).to start_with('/home/user/.ssh/config.d/vagrant/')
      expect(path).to end_with('-web.conf')
    end
  end

  describe '#generate_ssh_config_content' do
    it 'generates valid SSH config content' do
      content = file_manager.generate_ssh_config_content(machine)
      
      expect(content).to include('Host ')
      expect(content).to include('HostName 192.168.33.10')
      expect(content).to include('Port 2222')
      expect(content).to include('User vagrant')
      expect(content).to include('IdentityFile /home/user/.vagrant/machines/web/virtualbox/private_key')
      expect(content).to include('StrictHostKeyChecking no')
    end

    it 'includes project metadata in comments' do
      content = file_manager.generate_ssh_config_content(machine)
      
      expect(content).to include('# Managed by vagrant-ssh-config-manager plugin')
      expect(content).to include('# Project: project')
      expect(content).to include('# VM: web')
      expect(content).to include('# Generated:')
    end

    it 'returns nil when ssh_info is not available' do
      allow(machine).to receive(:ssh_info).and_return(nil)
      
      content = file_manager.generate_ssh_config_content(machine)
      expect(content).to be_nil
    end

    it 'handles missing private key path gracefully' do
      ssh_info_no_key = ssh_info.dup
      ssh_info_no_key.delete(:private_key_path)
      allow(machine).to receive(:ssh_info).and_return(ssh_info_no_key)
      
      content = file_manager.generate_ssh_config_content(machine)
      expect(content).to include('Host ')
      expect(content).not_to include('IdentityFile')
    end
  end

  describe '#write_ssh_config_file' do
    let(:file_path) { '/home/user/.ssh/config.d/vagrant/abc12345-web.conf' }
    let(:temp_file) { instance_double('Tempfile', write: nil, close: nil, path: '/tmp/tempfile', unlink: nil) }
    
    before do
      allow(file_manager).to receive(:file_path).and_return(file_path)
      allow(file_manager).to receive(:generate_ssh_config_content).and_return("Host web\n  HostName 192.168.33.10")
      allow(Tempfile).to receive(:new).and_return(temp_file)
      allow(File).to receive(:chmod)
      allow(FileUtils).to receive(:mv)
      allow(File).to receive(:exist?).with(temp_file.path).and_return(false)
    end

    context 'when plugin is enabled' do
      it 'creates directory and writes file atomically' do
        expect(FileUtils).to receive(:mkdir_p).with('/home/user/.ssh/config.d/vagrant', mode: 0700)
        expect(temp_file).to receive(:write).with("Host web\n  HostName 192.168.33.10")
        expect(File).to receive(:chmod).with(0600, '/tmp/tempfile')
        expect(FileUtils).to receive(:mv).with('/tmp/tempfile', anything)
        
        result = file_manager.write_ssh_config_file(machine)
        expect(result).to be true
      end

      it 'cleans up temp file on error' do
        allow(temp_file).to receive(:write).and_raise(StandardError.new('Write failed'))
        allow(File).to receive(:exist?).with(temp_file.path).and_return(true)
        
        expect(temp_file).to receive(:unlink)
        
        result = file_manager.write_ssh_config_file(machine)
        expect(result).to be false
      end
    end

    context 'when plugin is disabled' do
      before do
        allow(config).to receive(:enabled).and_return(false)
      end

      it 'returns false without writing file' do
        expect(FileUtils).not_to receive(:mkdir_p)
        expect(temp_file).not_to receive(:write)
        
        result = file_manager.write_ssh_config_file(machine)
        expect(result).to be false
      end
    end

    context 'when content generation fails' do
      before do
        allow(file_manager).to receive(:generate_ssh_config_content).and_return(nil)
      end

      it 'returns false without writing file' do
        expect(temp_file).not_to receive(:write)
        
        result = file_manager.write_ssh_config_file(machine)
        expect(result).to be false
      end
    end
  end

  describe '#remove_ssh_config_file' do
    let(:file_path) { '/home/user/.ssh/config.d/vagrant/abc12345-web.conf' }
    
    before do
      allow(file_manager).to receive(:file_path).and_return(file_path)
    end

    context 'when file exists' do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:delete)
      end

      it 'deletes the file' do
        expect(File).to receive(:delete).with(file_path)
        
        result = file_manager.remove_ssh_config_file(machine)
        expect(result).to be true
      end

      it 'cleans up empty directory when configured' do
        allow(Dir).to receive(:exist?).with('/home/user/.ssh/config.d/vagrant').and_return(true)
        allow(Dir).to receive(:entries).with('/home/user/.ssh/config.d/vagrant').and_return(['.', '..'])
        allow(Dir).to receive(:rmdir)
        
        result = file_manager.remove_ssh_config_file(machine)
        expect(result).to be true
      end
    end

    context 'when file does not exist' do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(false)
      end

      it 'returns false without attempting deletion' do
        expect(File).not_to receive(:delete)
        
        result = file_manager.remove_ssh_config_file(machine)
        expect(result).to be false
      end
    end

    context 'when deletion fails' do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:delete).and_raise(StandardError.new('Permission denied'))
      end

      it 'returns false and logs error' do
        result = file_manager.remove_ssh_config_file(machine)
        expect(result).to be false
      end
    end
  end

  describe '#ssh_config_file_exists?' do
    let(:file_path) { '/home/user/.ssh/config.d/vagrant/abc12345-web.conf' }
    
    before do
      allow(file_manager).to receive(:file_path).and_return(file_path)
    end

    it 'returns true when file exists' do
      allow(File).to receive(:exist?).with(file_path).and_return(true)
      
      result = file_manager.ssh_config_file_exists?(machine)
      expect(result).to be true
    end

    it 'returns false when file does not exist' do
      allow(File).to receive(:exist?).with(file_path).and_return(false)
      
      result = file_manager.ssh_config_file_exists?(machine)
      expect(result).to be false
    end
  end

  describe '#validate_ssh_config_content?' do
    it 'validates valid SSH config content' do
      content = "Host web\nHostName 192.168.33.10\nPort 2222"
      
      result = file_manager.validate_ssh_config_content?(content)
      expect(result).to be true
    end

    it 'rejects empty content' do
      result = file_manager.validate_ssh_config_content?('')
      expect(result).to be false
    end

    it 'rejects nil content' do
      result = file_manager.validate_ssh_config_content?(nil)
      expect(result).to be false
    end

    it 'rejects content missing required elements' do
      content = "Host web\nUser vagrant"
      
      result = file_manager.validate_ssh_config_content?(content)
      expect(result).to be false
    end
  end

  describe '#cleanup_orphaned_files' do
    let(:config_dir) { '/home/user/.ssh/config.d/vagrant' }
    let(:old_file) { File.join(config_dir, 'abc12345-old.conf') }
    let(:recent_file) { File.join(config_dir, 'def67890-recent.conf') }
    
    before do
      allow(Dir).to receive(:exist?).with(config_dir).and_return(true)
      allow(Dir).to receive(:glob).with(File.join(config_dir, '*.conf')).and_return([old_file, recent_file])
      allow(File).to receive(:file?).and_return(true)
      allow(File).to receive(:mtime).with(old_file).and_return(Time.now - (35 * 24 * 60 * 60)) # 35 days old
      allow(File).to receive(:mtime).with(recent_file).and_return(Time.now - (5 * 24 * 60 * 60)) # 5 days old
    end

    it 'identifies files older than 30 days as orphaned' do
      orphaned_files = file_manager.cleanup_orphaned_files
      
      expect(orphaned_files).to have_attributes(length: 1)
      expect(orphaned_files.first[:path]).to eq(old_file)
      expect(orphaned_files.first[:age_days]).to be >= 30
    end

    it 'does not identify recent files as orphaned' do
      orphaned_files = file_manager.cleanup_orphaned_files
      
      orphaned_paths = orphaned_files.map { |f| f[:path] }
      expect(orphaned_paths).not_to include(recent_file)
    end

    it 'returns nil when directory does not exist' do
      allow(Dir).to receive(:exist?).with(config_dir).and_return(false)
      
      orphaned_files = file_manager.cleanup_orphaned_files
      expect(orphaned_files).to be_nil
    end
  end

  describe '#remove_orphaned_files' do
    let(:orphaned_files) do
      [
        { path: '/path/to/old1.conf', age_days: 35 },
        { path: '/path/to/old2.conf', age_days: 40 }
      ]
    end

    before do
      allow(file_manager).to receive(:cleanup_orphaned_files).and_return(orphaned_files)
      allow(File).to receive(:delete)
    end

    it 'removes all orphaned files' do
      expect(File).to receive(:delete).with('/path/to/old1.conf')
      expect(File).to receive(:delete).with('/path/to/old2.conf')
      
      result = file_manager.remove_orphaned_files
      expect(result).to eq(2)
    end

    it 'handles deletion errors gracefully' do
      allow(File).to receive(:delete).with('/path/to/old1.conf').and_raise(StandardError.new('Permission denied'))
      allow(File).to receive(:delete).with('/path/to/old2.conf')
      
      result = file_manager.remove_orphaned_files
      expect(result).to eq(1)
    end

    it 'cleans up empty directory when files are removed' do
      allow(config).to receive(:cleanup_empty_dir).and_return(true)
      
      expect(file_manager).to receive(:cleanup_empty_directory)
      
      file_manager.remove_orphaned_files
    end
  end

  describe '#get_all_config_files' do
    let(:config_dir) { '/home/user/.ssh/config.d/vagrant' }
    
    it 'returns all .conf files in directory' do
      files = ['file1.conf', 'file2.conf']
      allow(Dir).to receive(:exist?).with(config_dir).and_return(true)
      allow(Dir).to receive(:glob).with(File.join(config_dir, '*.conf')).and_return(files)
      
      result = file_manager.get_all_config_files
      expect(result).to eq(files)
    end

    it 'returns empty array when directory does not exist' do
      allow(Dir).to receive(:exist?).with(config_dir).and_return(false)
      
      result = file_manager.get_all_config_files
      expect(result).to be_empty
    end
  end

  describe 'private methods' do
    describe '#generate_project_hash' do
      it 'generates consistent 8-character hash' do
        hash1 = file_manager.send(:generate_project_hash, '/home/user/project')
        hash2 = file_manager.send(:generate_project_hash, '/home/user/project')
        
        expect(hash1).to eq(hash2)
        expect(hash1).to match(/^[a-f0-9]{8}$/)
      end

      it 'generates different hashes for different paths' do
        hash1 = file_manager.send(:generate_project_hash, '/home/user/project1')
        hash2 = file_manager.send(:generate_project_hash, '/home/user/project2')
        
        expect(hash1).not_to eq(hash2)
      end
    end

    describe '#generate_host_name' do
      context 'with project isolation enabled' do
        it 'combines project name and machine name' do
          host_name = file_manager.send(:generate_host_name, machine)
          expect(host_name).to eq('project-web')
        end
      end

      context 'with project isolation disabled' do
        before do
          allow(config).to receive(:project_isolation).and_return(false)
        end

        it 'uses only machine name' do
          host_name = file_manager.send(:generate_host_name, machine)
          expect(host_name).to eq('web')
        end
      end
    end

    describe '#cleanup_empty_directory' do
      let(:config_dir) { '/home/user/.ssh/config.d/vagrant' }
      
      before do
        allow(Dir).to receive(:exist?).with(config_dir).and_return(true)
      end

      context 'when directory is empty' do
        before do
          allow(Dir).to receive(:entries).with(config_dir).and_return(['.', '..'])
          allow(Dir).to receive(:rmdir)
        end

        it 'removes empty directory' do
          expect(Dir).to receive(:rmdir).with(config_dir)
          
          file_manager.send(:cleanup_empty_directory)
        end

        context 'with manage_includes enabled' do
          before do
            allow(config).to receive(:manage_includes).and_return(true)
          end

          it 'removes include directive before removing directory' do
            include_manager = instance_double('IncludeManager')
            allow(VagrantPlugins::SshConfigManager::IncludeManager).to receive(:new).with(config).and_return(include_manager)
            expect(include_manager).to receive(:remove_include_directive)
            
            file_manager.send(:cleanup_empty_directory)
          end
        end
      end

      context 'when directory is not empty' do
        before do
          allow(Dir).to receive(:entries).with(config_dir).and_return(['.', '..', 'some_file.conf'])
        end

        it 'does not remove directory' do
          expect(Dir).not_to receive(:rmdir)
          
          file_manager.send(:cleanup_empty_directory)
        end
      end

      context 'when directory removal fails' do
        before do
          allow(Dir).to receive(:entries).with(config_dir).and_return(['.', '..'])
          allow(Dir).to receive(:rmdir).and_raise(StandardError.new('Permission denied'))
        end

        it 'handles error gracefully' do
          expect { file_manager.send(:cleanup_empty_directory) }.not_to raise_error
        end
      end
    end
  end
end
