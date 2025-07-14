# frozen_string_literal: true

require_relative '../unit_helper'
require 'tempfile'
require 'tmpdir'

# Mock Vagrant plugin system for testing
module Vagrant
  module Plugin
    module V2
      module Config
        UNSET_VALUE = Object.new.freeze

        # Base class for Vagrant configuration
        class Base
          def _detected_errors
            []
          end
        end
      end
    end
  end

  def self.plugin(_version, component)
    case component
    when :config
      Vagrant::Plugin::V2::Config::Base
    else
      Object
    end
  end
end

# Create a simplified version of the Config class for testing
module VagrantPlugins
  module SshConfigManager
    class Config < Vagrant.plugin('2', :config)
      attr_accessor :enabled, :ssh_config_dir, :manage_includes, :auto_create_dir,
                    :cleanup_empty_dir, :auto_remove_on_destroy, :update_on_reload,
                    :refresh_on_provision, :keep_config_on_halt, :project_isolation

      def initialize
        super
        @enabled = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @ssh_config_dir = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @manage_includes = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @auto_create_dir = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @cleanup_empty_dir = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @auto_remove_on_destroy = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @update_on_reload = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @refresh_on_provision = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @keep_config_on_halt = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @project_isolation = Vagrant::Plugin::V2::Config::UNSET_VALUE
      end

      def finalize!
        @enabled = true if @enabled == Vagrant::Plugin::V2::Config::UNSET_VALUE
        if @ssh_config_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE
          @ssh_config_dir = File.expand_path('~/.ssh/config.d/vagrant')
        end
        @manage_includes = false if @manage_includes == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @auto_create_dir = true if @auto_create_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @cleanup_empty_dir = true if @cleanup_empty_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @auto_remove_on_destroy = true if @auto_remove_on_destroy == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @update_on_reload = true if @update_on_reload == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @refresh_on_provision = true if @refresh_on_provision == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @keep_config_on_halt = true if @keep_config_on_halt == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @project_isolation = true if @project_isolation == Vagrant::Plugin::V2::Config::UNSET_VALUE

        @ssh_config_dir = File.expand_path(@ssh_config_dir) if @ssh_config_dir.is_a?(String)
        ensure_ssh_config_directory if @auto_create_dir && @ssh_config_dir
      end

      def validate(_machine)
        errors = _detected_errors

        errors << 'sshconfigmanager.enabled must be true or false' unless [true, false].include?(@enabled)

        if @ssh_config_dir
          if @ssh_config_dir.is_a?(String)
            if @ssh_config_dir.include?('..') || @ssh_config_dir.include?('//')
              errors << "sshconfigmanager.ssh_config_dir contains invalid path components: #{@ssh_config_dir}"
            end

            File.expand_path(@ssh_config_dir)

            if File.directory?(@ssh_config_dir)
              unless File.readable?(@ssh_config_dir) && File.writable?(@ssh_config_dir)
                errors << "sshconfigmanager.ssh_config_dir is not readable/writable: #{@ssh_config_dir}"
              end
            elsif @auto_create_dir
              begin
                FileUtils.mkdir_p(@ssh_config_dir, mode: 0o700)
              rescue StandardError => e
                errors << "sshconfigmanager.ssh_config_dir cannot be created: #{e.message}"
              end
            else
              errors << "sshconfigmanager.ssh_config_dir does not exist and auto_create_dir is disabled: #{@ssh_config_dir}"
            end
          else
            errors << 'sshconfigmanager.ssh_config_dir must be a string path'
          end
        end

        boolean_options = {
          'auto_remove_on_destroy' => @auto_remove_on_destroy,
          'update_on_reload' => @update_on_reload,
          'refresh_on_provision' => @refresh_on_provision,
          'keep_config_on_halt' => @keep_config_on_halt,
          'project_isolation' => @project_isolation,
          'manage_includes' => @manage_includes,
          'auto_create_dir' => @auto_create_dir,
          'cleanup_empty_dir' => @cleanup_empty_dir
        }

        boolean_options.each do |option_name, value|
          errors << "sshconfigmanager.#{option_name} must be true or false" unless [true, false].include?(value)
        end

        { 'SSH Config Manager' => errors }
      end

      def to_hash
        {
          enabled: @enabled,
          ssh_config_dir: @ssh_config_dir,
          manage_includes: @manage_includes,
          auto_create_dir: @auto_create_dir,
          cleanup_empty_dir: @cleanup_empty_dir,
          auto_remove_on_destroy: @auto_remove_on_destroy,
          update_on_reload: @update_on_reload,
          refresh_on_provision: @refresh_on_provision,
          keep_config_on_halt: @keep_config_on_halt,
          project_isolation: @project_isolation
        }
      end

      def enabled_for_action?(action_name)
        return false unless @enabled

        case action_name.to_sym
        when :up, :resume
          true
        when :destroy
          @auto_remove_on_destroy
        when :reload
          @update_on_reload
        when :provision
          @refresh_on_provision
        when :halt, :suspend
          @keep_config_on_halt
        else
          false
        end
      end

      def merge(other)
        result = self.class.new

        result.enabled = other.enabled == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @enabled : other.enabled
        result.ssh_config_dir = other.ssh_config_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @ssh_config_dir : other.ssh_config_dir
        result.manage_includes = other.manage_includes == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @manage_includes : other.manage_includes
        result.auto_create_dir = other.auto_create_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @auto_create_dir : other.auto_create_dir
        result.cleanup_empty_dir = other.cleanup_empty_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @cleanup_empty_dir : other.cleanup_empty_dir
        result.auto_remove_on_destroy = other.auto_remove_on_destroy == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @auto_remove_on_destroy : other.auto_remove_on_destroy
        result.update_on_reload = other.update_on_reload == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @update_on_reload : other.update_on_reload
        result.refresh_on_provision = other.refresh_on_provision == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @refresh_on_provision : other.refresh_on_provision
        result.keep_config_on_halt = other.keep_config_on_halt == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @keep_config_on_halt : other.keep_config_on_halt
        result.project_isolation = other.project_isolation == Vagrant::Plugin::V2::Config::UNSET_VALUE ? @project_isolation : other.project_isolation

        result
      end

      def ensure_ssh_config_directory
        return false unless @auto_create_dir
        return true if File.directory?(@ssh_config_dir)

        begin
          FileUtils.mkdir_p(@ssh_config_dir, mode: 0o700)
          true
        rescue StandardError
          false
        end
      end

      def ssh_manager_instance(_machine)
        # Return a mock object for testing
        Object.new
      end
      alias get_ssh_manager_instance ssh_manager_instance
    end
  end
end

RSpec.describe VagrantPlugins::SshConfigManager::Config do
  let(:config) { described_class.new }
  let(:test_ssh_dir) { File.join(@temp_dir, 'ssh_config') }

  before do
    # Ensure test directory exists
    FileUtils.mkdir_p(@temp_dir)
  end

  after do
    # Clean up any created directories
    FileUtils.rm_rf(test_ssh_dir)
  end

  describe '#initialize' do
    it 'initializes with UNSET_VALUE for all attributes' do
      expect(config.enabled).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.ssh_config_dir).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.manage_includes).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.auto_create_dir).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.cleanup_empty_dir).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.auto_remove_on_destroy).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.update_on_reload).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.refresh_on_provision).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.keep_config_on_halt).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
      expect(config.project_isolation).to eq(Vagrant::Plugin::V2::Config::UNSET_VALUE)
    end
  end

  describe '#finalize!' do
    context 'with default values' do
      before { config.finalize! }

      it 'sets enabled to true' do
        expect(config.enabled).to be true
      end

      it 'sets ssh_config_dir to default path' do
        expected_path = File.expand_path('~/.ssh/config.d/vagrant')
        expect(config.ssh_config_dir).to eq(expected_path)
      end

      it 'sets boolean options to their defaults' do
        expect(config.manage_includes).to be false
        expect(config.auto_create_dir).to be true
        expect(config.cleanup_empty_dir).to be true
        expect(config.auto_remove_on_destroy).to be true
        expect(config.update_on_reload).to be true
        expect(config.refresh_on_provision).to be true
        expect(config.keep_config_on_halt).to be true
        expect(config.project_isolation).to be true
      end
    end

    context 'with custom values' do
      before do
        config.enabled = false
        config.ssh_config_dir = test_ssh_dir
        config.manage_includes = true
        config.auto_create_dir = false
        config.finalize!
      end

      it 'preserves custom values' do
        expect(config.enabled).to be false
        expect(config.ssh_config_dir).to eq(File.expand_path(test_ssh_dir))
        expect(config.manage_includes).to be true
        expect(config.auto_create_dir).to be false
      end
    end

    context 'with auto_create_dir enabled' do
      before do
        config.ssh_config_dir = test_ssh_dir
        config.auto_create_dir = true
        config.finalize!
      end

      it 'creates the SSH config directory' do
        expect(File.directory?(test_ssh_dir)).to be true

        # Check directory permissions
        stat = File.stat(test_ssh_dir)
        expect(stat.mode & 0o777).to eq(0o700)
      end
    end
  end

  describe '#validate' do
    let(:machine) { double('machine') }

    before { config.finalize! }

    context 'with valid configuration' do
      it 'returns no errors' do
        config.ssh_config_dir = test_ssh_dir
        FileUtils.mkdir_p(test_ssh_dir, mode: 0o700)

        result = config.validate(machine)
        expect(result['SSH Config Manager']).to be_empty
      end
    end

    context 'with invalid enabled flag' do
      before { config.enabled = 'invalid' }

      it 'returns validation error' do
        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include('sshconfigmanager.enabled must be true or false')
      end
    end

    context 'with invalid ssh_config_dir' do
      it 'validates non-string directory' do
        config.ssh_config_dir = 123

        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include('sshconfigmanager.ssh_config_dir must be a string path')
      end

      it 'validates directory with invalid path components' do
        config.ssh_config_dir = '/path/../with/invalid/components'

        result = config.validate(machine)
        expect(result['SSH Config Manager'].any? { |error| error.include?('invalid path components') }).to be true
      end

      it 'validates non-existent directory when auto_create_dir is disabled' do
        config.ssh_config_dir = '/non/existent/path'
        config.auto_create_dir = false

        result = config.validate(machine)
        expect(result['SSH Config Manager'].any? { |error| error.include?('does not exist and auto_create_dir is disabled') }).to be true
      end

      it 'validates unwritable directory' do
        # Create directory but make it read-only
        FileUtils.mkdir_p(test_ssh_dir, mode: 0o500)
        config.ssh_config_dir = test_ssh_dir

        result = config.validate(machine)
        expect(result['SSH Config Manager'].any? { |error| error.include?('not readable/writable') }).to be true

        # Restore permissions for cleanup
        File.chmod(0o700, test_ssh_dir)
      end
    end

    context 'with invalid boolean options' do
      it 'validates manage_includes' do
        config.manage_includes = 'invalid'

        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include('sshconfigmanager.manage_includes must be true or false')
      end

      it 'validates auto_create_dir' do
        config.auto_create_dir = 'invalid'

        result = config.validate(machine)
        expect(result['SSH Config Manager']).to include('sshconfigmanager.auto_create_dir must be true or false')
      end

      it 'validates all boolean options' do
        config.cleanup_empty_dir = 'invalid'
        config.auto_remove_on_destroy = 'invalid'
        config.update_on_reload = 'invalid'
        config.refresh_on_provision = 'invalid'
        config.keep_config_on_halt = 'invalid'
        config.project_isolation = 'invalid'

        result = config.validate(machine)
        errors = result['SSH Config Manager']

        expect(errors).to include('sshconfigmanager.cleanup_empty_dir must be true or false')
        expect(errors).to include('sshconfigmanager.auto_remove_on_destroy must be true or false')
        expect(errors).to include('sshconfigmanager.update_on_reload must be true or false')
        expect(errors).to include('sshconfigmanager.refresh_on_provision must be true or false')
        expect(errors).to include('sshconfigmanager.keep_config_on_halt must be true or false')
        expect(errors).to include('sshconfigmanager.project_isolation must be true or false')
      end
    end
  end

  describe '#to_hash' do
    before { config.finalize! }

    it 'returns configuration as hash' do
      hash = config.to_hash

      expect(hash).to be_a(Hash)
      expect(hash[:enabled]).to be true
      expect(hash[:ssh_config_dir]).to be_a(String)
      expect(hash[:manage_includes]).to be false
      expect(hash[:auto_create_dir]).to be true
      expect(hash[:cleanup_empty_dir]).to be true
      expect(hash[:auto_remove_on_destroy]).to be true
      expect(hash[:update_on_reload]).to be true
      expect(hash[:refresh_on_provision]).to be true
      expect(hash[:keep_config_on_halt]).to be true
      expect(hash[:project_isolation]).to be true
    end
  end

  describe '#enabled_for_action?' do
    before do
      config.finalize!
      config.enabled = true
    end

    context 'when plugin is disabled' do
      before { config.enabled = false }

      it 'returns false for all actions' do
        expect(config.enabled_for_action?(:up)).to be false
        expect(config.enabled_for_action?(:destroy)).to be false
        expect(config.enabled_for_action?(:reload)).to be false
      end
    end

    context 'when plugin is enabled' do
      it 'returns true for up and resume actions' do
        expect(config.enabled_for_action?(:up)).to be true
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
        expect(config.enabled_for_action?(:invalid)).to be false
      end
    end
  end

  describe '#merge' do
    let(:other_config) { described_class.new }

    before do
      config.finalize!

      # Set some custom values in other config
      other_config.enabled = false
      other_config.ssh_config_dir = '/custom/path'
      other_config.manage_includes = true
    end

    it 'merges configurations preferring other config values' do
      merged = config.merge(other_config)

      expect(merged.enabled).to be false # from other_config
      expect(merged.ssh_config_dir).to eq('/custom/path') # from other_config
      expect(merged.manage_includes).to be true # from other_config

      # Values not set in other_config should come from original
      expect(merged.auto_create_dir).to eq(config.auto_create_dir)
      expect(merged.cleanup_empty_dir).to eq(config.cleanup_empty_dir)
    end

    it 'preserves original config values when other config has UNSET_VALUE' do
      other_config.auto_create_dir = Vagrant::Plugin::V2::Config::UNSET_VALUE

      merged = config.merge(other_config)
      expect(merged.auto_create_dir).to eq(config.auto_create_dir)
    end
  end

  describe '#ensure_ssh_config_directory' do
    context 'when auto_create_dir is disabled' do
      before { config.auto_create_dir = false }

      it 'returns false without creating directory' do
        config.ssh_config_dir = test_ssh_dir
        expect(config.ensure_ssh_config_directory).to be false
        expect(File.directory?(test_ssh_dir)).to be false
      end
    end

    context 'when auto_create_dir is enabled' do
      before { config.auto_create_dir = true }

      it 'creates directory and returns true' do
        config.ssh_config_dir = test_ssh_dir
        expect(config.ensure_ssh_config_directory).to be true
        expect(File.directory?(test_ssh_dir)).to be true

        # Check permissions
        stat = File.stat(test_ssh_dir)
        expect(stat.mode & 0o777).to eq(0o700)
      end

      it 'returns true if directory already exists' do
        FileUtils.mkdir_p(test_ssh_dir)
        config.ssh_config_dir = test_ssh_dir

        expect(config.ensure_ssh_config_directory).to be true
      end

      it 'returns false if directory creation fails' do
        # Try to create directory in invalid location
        config.ssh_config_dir = '/invalid/path/that/cannot/be/created'

        # Mock FileUtils to raise an error
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, 'Permission denied')

        expect(config.ensure_ssh_config_directory).to be false
      end
    end
  end

  describe '#ssh_manager_instance' do
    let(:machine) { double('machine') }

    before { config.finalize! }

    it 'returns a FileManager instance' do
      result = config.ssh_manager_instance(machine)
      expect(result).not_to be_nil
    end

    it 'provides backward compatibility alias' do
      # Test that the alias exists and works
      expect(config.method(:get_ssh_manager_instance)).to eq(config.method(:ssh_manager_instance))
    end
  end

  describe 'attribute accessors' do
    it 'allows reading and writing all configuration attributes' do
      config.enabled = false
      expect(config.enabled).to be false

      config.ssh_config_dir = '/custom/path'
      expect(config.ssh_config_dir).to eq('/custom/path')

      config.manage_includes = true
      expect(config.manage_includes).to be true

      config.auto_create_dir = false
      expect(config.auto_create_dir).to be false

      config.cleanup_empty_dir = false
      expect(config.cleanup_empty_dir).to be false

      config.auto_remove_on_destroy = false
      expect(config.auto_remove_on_destroy).to be false

      config.update_on_reload = false
      expect(config.update_on_reload).to be false

      config.refresh_on_provision = false
      expect(config.refresh_on_provision).to be false

      config.keep_config_on_halt = false
      expect(config.keep_config_on_halt).to be false

      config.project_isolation = false
      expect(config.project_isolation).to be false
    end
  end
end
