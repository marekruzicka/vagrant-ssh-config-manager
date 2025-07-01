require 'spec_helper'

RSpec.describe VagrantPlugins::SshConfigManager::Config do
  let(:machine) { create_mock_machine }
  let(:config) { described_class.new }

  include_examples 'configuration validation'

  describe '#initialize' do
    it 'initializes all attributes to UNSET_VALUE' do
      expect(config.enabled).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
      expect(config.ssh_conf_file).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
      expect(config.auto_remove_on_destroy).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
      expect(config.update_on_reload).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
      expect(config.refresh_on_provision).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
      expect(config.keep_config_on_halt).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
      expect(config.project_isolation).to eq(Vagrant.plugin("2", :config)::UNSET_VALUE)
    end
  end

  describe '#finalize!' do
    it 'sets default values for unset options' do
      config.finalize!
      
      expect(config.enabled).to be true
      expect(config.ssh_conf_file).to eq(File.expand_path('~/.ssh/config'))
      expect(config.auto_remove_on_destroy).to be true
      expect(config.update_on_reload).to be true
      expect(config.refresh_on_provision).to be true
      expect(config.keep_config_on_halt).to be true
      expect(config.project_isolation).to be true
    end

    it 'preserves explicitly set values' do
      config.enabled = false
      config.ssh_conf_file = '/custom/ssh/config'
      config.auto_remove_on_destroy = false
      
      config.finalize!
      
      expect(config.enabled).to be false
      expect(config.ssh_conf_file).to eq('/custom/ssh/config')
      expect(config.auto_remove_on_destroy).to be false
    end

    it 'expands file paths' do
      config.ssh_conf_file = '~/custom/ssh/config'
      config.finalize!
      
      expect(config.ssh_conf_file).to eq(File.expand_path('~/custom/ssh/config'))
    end

    it 'handles nil ssh_conf_file' do
      config.ssh_conf_file = nil
      expect { config.finalize! }.not_to raise_error
    end
  end

  describe '#validate' do
    before { config.finalize! }

    context 'with valid configuration' do
      it 'returns empty errors' do
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
      end
    end

    context 'enabled option validation' do
      it 'accepts true value' do
        config.enabled = true
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
      end

      it 'accepts false value' do
        config.enabled = false
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
      end

      it 'rejects non-boolean values' do
        config.enabled = 'yes'
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include(match(/enabled must be true or false/))
        
        config.enabled = 1
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include(match(/enabled must be true or false/))
      end
    end

    context 'ssh_conf_file option validation' do
      it 'accepts valid file path' do
        config.ssh_conf_file = @ssh_config_file
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
      end

      it 'accepts file path that does not exist yet' do
        config.ssh_conf_file = File.join(@temp_dir, 'new_ssh_config')
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
      end

      it 'rejects non-string values' do
        config.ssh_conf_file = 123
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include(match(/must be a string path/))
        
        config.ssh_conf_file = []
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include(match(/must be a string path/))
      end

      it 'validates directory creation' do
        config.ssh_conf_file = File.join(@temp_dir, 'new_dir', 'ssh_config')
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
        
        # Directory should have been created during validation
        expect(File.directory?(File.dirname(config.ssh_conf_file))).to be true
      end

      it 'detects unwritable existing files' do
        File.write(@ssh_config_file, 'test')
        File.chmod(0400, @ssh_config_file)
        
        config.ssh_conf_file = @ssh_config_file
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include(match(/is not writable/))
      end

      it 'handles directory creation errors' do
        # Create a read-only directory
        readonly_dir = File.join(@temp_dir, 'readonly')
        Dir.mkdir(readonly_dir)
        File.chmod(0400, readonly_dir)
        
        config.ssh_conf_file = File.join(readonly_dir, 'subdir', 'ssh_config')
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include(match(/directory cannot be created/))
      end
    end

    context 'boolean options validation' do
      %w[auto_remove_on_destroy update_on_reload refresh_on_provision keep_config_on_halt project_isolation].each do |option|
        it "validates #{option} as boolean" do
          config.send("#{option}=", 'not_boolean')
          result = config.validate(machine)
          expect(result['SSH Config Manager']).to include(match(/#{option} must be true or false/))
          
          config.send("#{option}=", true)
          result = config.validate(machine)
          expect(result['SSH Config Manager']).to be_empty
          
          config.send("#{option}=", false)
          result = config.validate(machine)
          expect(result['SSH Config Manager']).to be_empty
        end
      end
    end
  end

  describe '#to_hash' do
    before { config.finalize! }

    it 'returns configuration as hash' do
      result = config.to_hash
      
      expect(result).to be_a(Hash)
      expect(result[:enabled]).to eq(config.enabled)
      expect(result[:ssh_conf_file]).to eq(config.ssh_conf_file)
      expect(result[:auto_remove_on_destroy]).to eq(config.auto_remove_on_destroy)
      expect(result[:update_on_reload]).to eq(config.update_on_reload)
      expect(result[:refresh_on_provision]).to eq(config.refresh_on_provision)
      expect(result[:keep_config_on_halt]).to eq(config.keep_config_on_halt)
      expect(result[:project_isolation]).to eq(config.project_isolation)
    end
  end

  describe '#enabled_for_action?' do
    before { config.finalize! }

    it 'returns false when plugin is disabled' do
      config.enabled = false
      expect(config.enabled_for_action?(:up)).to be false
      expect(config.enabled_for_action?(:destroy)).to be false
    end

    context 'when plugin is enabled' do
      before { config.enabled = true }

      it 'returns true for up action' do
        expect(config.enabled_for_action?(:up)).to be true
      end

      it 'returns true for resume action' do
        expect(config.enabled_for_action?(:resume)).to be true
      end

      it 'respects auto_remove_on_destroy for destroy action' do
        config.auto_remove_on_destroy = true
        expect(config.enabled_for_action?(:destroy)).to be true
        
        config.auto_remove_on_destroy = false
        expect(config.enabled_for_action?(:destroy)).to be false
      end

      it 'respects update_on_reload for reload action' do
        config.update_on_reload = true
        expect(config.enabled_for_action?(:reload)).to be true
        
        config.update_on_reload = false
        expect(config.enabled_for_action?(:reload)).to be false
      end

      it 'respects refresh_on_provision for provision action' do
        config.refresh_on_provision = true
        expect(config.enabled_for_action?(:provision)).to be true
        
        config.refresh_on_provision = false
        expect(config.enabled_for_action?(:provision)).to be false
      end

      it 'respects keep_config_on_halt for halt and suspend actions' do
        config.keep_config_on_halt = true
        expect(config.enabled_for_action?(:halt)).to be true
        expect(config.enabled_for_action?(:suspend)).to be true
        
        config.keep_config_on_halt = false
        expect(config.enabled_for_action?(:halt)).to be false
        expect(config.enabled_for_action?(:suspend)).to be false
      end

      it 'returns false for unknown actions' do
        expect(config.enabled_for_action?(:unknown)).to be false
        expect(config.enabled_for_action?(:custom)).to be false
      end
    end
  end

  describe '#effective_ssh_config_file' do
    before { config.finalize! }

    it 'returns configured ssh_conf_file' do
      custom_path = File.join(@temp_dir, 'custom_ssh_config')
      config.ssh_conf_file = custom_path
      
      expect(config.effective_ssh_config_file).to eq(custom_path)
    end

    it 'returns default path when ssh_conf_file is nil' do
      config.ssh_conf_file = nil
      expected_path = File.expand_path('~/.ssh/config')
      
      expect(config.effective_ssh_config_file).to eq(expected_path)
    end

    it 'creates directory if it does not exist' do
      custom_path = File.join(@temp_dir, 'new_dir', 'ssh_config')
      config.ssh_conf_file = custom_path
      
      config.effective_ssh_config_file
      
      expect(File.directory?(File.dirname(custom_path))).to be true
    end
  end

  describe '#merge' do
    let(:other_config) { described_class.new }

    it 'merges configurations with other taking precedence' do
      config.enabled = true
      config.ssh_conf_file = '/original/path'
      config.finalize!
      
      other_config.enabled = false
      other_config.ssh_conf_file = '/new/path'
      other_config.finalize!
      
      result = config.merge(other_config)
      
      expect(result.enabled).to be false
      expect(result.ssh_conf_file).to eq('/new/path')
    end

    it 'preserves original values when other has UNSET_VALUE' do
      config.enabled = true
      config.ssh_conf_file = '/original/path'
      config.finalize!
      
      # other_config has UNSET_VALUE for all options
      
      result = config.merge(other_config)
      
      expect(result.enabled).to be true
      expect(result.ssh_conf_file).to eq('/original/path')
    end

    it 'creates new config object' do
      result = config.merge(other_config)
      
      expect(result).not_to eq(config)
      expect(result).not_to eq(other_config)
      expect(result).to be_a(described_class)
    end
  end
end
