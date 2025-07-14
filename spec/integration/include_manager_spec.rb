# frozen_string_literal: true

require_relative '../integration_helper'

RSpec.describe VagrantPlugins::SshConfigManager::IncludeManager, type: :integration do
  let(:config) { create_test_config }
  let(:include_manager) { described_class.new(config) }

  describe '#initialize' do
    it 'creates a new include manager with proper configuration' do
      expect(include_manager.instance_variable_get(:@config)).to eq(config)
    end
  end

  describe '#ssh_config_file' do
    it 'returns the main SSH config file path' do
      expect(include_manager.ssh_config_file).to eq(@ssh_config_file)
    end
  end

  describe '#include_directive_exists?' do
    context 'when SSH config file does not exist' do
      it 'returns false' do
        expect(include_manager.include_directive_exists?).to be false
      end
    end

    context 'when SSH config file exists without include' do
      before do
        File.write(@ssh_config_file, "Host example\n  HostName example.com\n")
      end

      it 'returns false' do
        expect(include_manager.include_directive_exists?).to be false
      end
    end

    context 'when SSH config file has the include' do
      before do
        File.write(@ssh_config_file, "# BEGIN vagrant-ssh-config-manager\nInclude #{@config_d_dir}/vagrant/*.conf\n# END vagrant-ssh-config-manager\nHost example\n  HostName example.com\n")
      end

      it 'returns true' do
        expect(include_manager.include_directive_exists?).to be true
      end
    end
  end

  describe '#add_include_directive' do
    context 'when SSH config file does not exist' do
      it 'creates the SSH config file with include directive' do
        include_manager.add_include_directive

        config_content = read_ssh_config
        expect(config_content).to include("Include #{@config_d_dir}/vagrant/*.conf")
        expect(config_content).to include('# BEGIN vagrant-ssh-config-manager')
        expect(config_content).to include('# END vagrant-ssh-config-manager')
      end
    end

    context 'when SSH config file exists without include' do
      before do
        File.write(@ssh_config_file, "Host example\n  HostName example.com\n")
      end

      it 'adds include directive at the beginning' do
        include_manager.add_include_directive

        config_content = read_ssh_config
        expect(config_content).to start_with("# BEGIN vagrant-ssh-config-manager\n")
        expect(config_content).to include("Include #{@config_d_dir}/vagrant/*.conf")
        expect(config_content).to include('Host example')
      end
    end

    context 'when SSH config file already has the include' do
      before do
        File.write(@ssh_config_file, "# BEGIN vagrant-ssh-config-manager\nInclude #{@config_d_dir}/vagrant/*.conf\n# END vagrant-ssh-config-manager\nHost example\n  HostName example.com\n")
      end

      it 'does not duplicate the include directive' do
        include_manager.add_include_directive

        config_content = read_ssh_config
        include_count = config_content.scan(/Include.*vagrant.*\.conf/).length
        expect(include_count).to eq(1)
      end
    end
  end

  describe '#remove_include_directive' do
    before do
      # Setup initial state with include
      File.write(@ssh_config_file, "# BEGIN vagrant-ssh-config-manager\nInclude #{@config_d_dir}/vagrant/*.conf\n# END vagrant-ssh-config-manager\nHost example\n  HostName example.com\n")
    end

    it 'removes the include directive' do
      include_manager.remove_include_directive

      config_content = read_ssh_config
      expect(config_content).not_to include("Include #{@config_d_dir}/vagrant/*.conf")
      expect(config_content).not_to include('# BEGIN vagrant-ssh-config-manager')
      expect(config_content).to include('Host example')
    end
  end

  describe '#should_remove_include_directive?' do
    context 'when config directory is empty' do
      it 'returns true' do
        expect(include_manager.should_remove_include_directive?).to be true
      end
    end

    context 'when config directory has files' do
      before do
        File.write(File.join(@vagrant_config_dir, 'test-vm.conf'), "Host test-vm\n  HostName 192.168.1.10\n")
      end

      it 'returns false' do
        expect(include_manager.should_remove_include_directive?).to be false
      end
    end

    context 'when config directory does not exist' do
      before do
        FileUtils.rm_rf(@vagrant_config_dir)
      end

      it 'returns true' do
        expect(include_manager.should_remove_include_directive?).to be true
      end
    end
  end

  describe '#manage_include_directive' do
    context 'when config directory has files' do
      before do
        File.write(File.join(@vagrant_config_dir, 'test-vm.conf'), "Host test-vm\n")
      end

      it 'adds include directive' do
        include_manager.manage_include_directive

        config_content = read_ssh_config
        expect(config_content).to include("Include #{@config_d_dir}/vagrant/*.conf")
      end
    end

    context 'when config directory is empty and include exists' do
      before do
        File.write(@ssh_config_file, "# BEGIN vagrant-ssh-config-manager\nInclude #{@config_d_dir}/vagrant/*.conf\n# END vagrant-ssh-config-manager\nHost example\n")
      end

      it 'removes include directive' do
        include_manager.manage_include_directive

        config_content = read_ssh_config
        expect(config_content).not_to include("Include #{@config_d_dir}/vagrant/*.conf")
        expect(config_content).to include('Host example')
      end
    end
  end
end
