# frozen_string_literal: true

require 'vagrant_ssh_config_manager/version'
require 'vagrant_ssh_config_manager/plugin'

module VagrantPlugins
  module SshConfigManager
    # Main plugin entry point
    # This file is loaded when the plugin is activated

    # Lazy load other components only when needed
    def self.require_file_manager
      require 'vagrant-ssh-config-manager/file_manager' unless defined?(FileManager)
    end

    def self.require_include_manager
      require 'vagrant-ssh-config-manager/include_manager' unless defined?(IncludeManager)
    end

    def self.require_ssh_info_extractor
      require 'vagrant-ssh-config-manager/ssh_info_extractor' unless defined?(SshInfoExtractor)
    end

    def self.require_file_locker
      require 'vagrant-ssh-config-manager/file_locker' unless defined?(FileLocker)
    end

    def self.require_config
      require 'vagrant-ssh-config-manager/config' unless defined?(Config)
    end
  end
end
