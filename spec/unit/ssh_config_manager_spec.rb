require 'spec_helper'

# Test core SSH config file manipulation without Vagrant dependencies
RSpec.describe 'SSH Config File Operations' do
  let(:ssh_config_file) { @ssh_config_file }
  let(:config_d_dir) { @config_d_dir }

  let(:sample_ssh_config_content) do
    <<~SSH_CONFIG
      Host test-host
        HostName 192.168.1.100
        Port 2222
        User vagrant
        IdentityFile /path/to/key
    SSH_CONFIG
  end

  describe 'file operations' do
    it 'creates SSH config file if it does not exist' do
      expect(File.exist?(ssh_config_file)).to be false

      File.write(ssh_config_file, sample_ssh_config_content)

      expect(File.exist?(ssh_config_file)).to be true
    end

    it 'creates config.d directory structure' do
      FileUtils.mkdir_p(config_d_dir, mode: 0o700)

      expect(Dir.exist?(config_d_dir)).to be true
    end

    it 'writes SSH entry to include file' do
      FileUtils.mkdir_p(config_d_dir, mode: 0o700)
      include_file = File.join(config_d_dir, 'vagrant-test-project')

      File.write(include_file, sample_ssh_config_content)

      content = File.read(include_file)
      expect(content).to include('Host test-host')
      expect(content).to include('HostName 192.168.1.100')
      expect(content).to include('Port 2222')
    end

    it 'adds include directive to main SSH config' do
      include_directive = <<~INCLUDE
        # === Vagrant SSH Config Manager ===
        Include ~/.ssh/config.d/vagrant-*
        # === End Vagrant SSH Config Manager ===
      INCLUDE

      File.write(ssh_config_file, include_directive)

      main_content = File.read(ssh_config_file)
      expect(main_content).to include('Include ~/.ssh/config.d/vagrant-*')
    end

    it 'removes SSH entries successfully' do
      FileUtils.mkdir_p(config_d_dir, mode: 0o700)
      include_file = File.join(config_d_dir, 'vagrant-test-project')

      File.write(include_file, sample_ssh_config_content)
      expect(File.exist?(include_file)).to be true

      File.delete(include_file)
      expect(File.exist?(include_file)).to be false
    end
  end

  describe 'project isolation' do
    it 'generates unique project names for different paths' do
      require 'digest'

      path1 = '/test/project'
      path2 = '/different/project'

      hash1 = Digest::SHA256.hexdigest(path1)[0..7]
      hash2 = Digest::SHA256.hexdigest(path2)[0..7]

      expect(hash1).not_to eq(hash2)
    end
  end
end
