# frozen_string_literal: true

require 'fileutils'
require 'vagrant'

module VagrantPlugins
  module SshConfigManager
    class Config < Vagrant.plugin('2', :config)
      # Plugin enabled/disabled flag
      attr_accessor :enabled

      # SSH config directory configuration
      attr_accessor :ssh_config_dir
      attr_accessor :manage_includes, :auto_create_dir, :cleanup_empty_dir, :update_on_reload, :refresh_on_provision,
                    :keep_config_on_halt, :project_isolation

      # Additional configuration options
      attr_accessor :auto_remove_on_destroy

      def initialize
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
        # Set default values for unset configuration options
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

        # Expand and validate file paths
        @ssh_config_dir = File.expand_path(@ssh_config_dir) if @ssh_config_dir.is_a?(String)

        # Ensure SSH config directory exists if auto_create_dir is enabled
        ensure_ssh_config_directory if @auto_create_dir && @ssh_config_dir
      end

      def validate(_machine)
        errors = _detected_errors

        # Validate enabled flag
        errors << 'sshconfigmanager.enabled must be true or false' unless [true, false].include?(@enabled)

        # Validate SSH config directory
        if @ssh_config_dir
          if @ssh_config_dir.is_a?(String)
            # Validate directory path format
            expanded_path = File.expand_path(@ssh_config_dir)
            if expanded_path.include?('..') || expanded_path.include?('//')
              errors << "sshconfigmanager.ssh_config_dir contains invalid path components: #{@ssh_config_dir}"
            end

            # Check if the directory exists or can be created
            if File.directory?(@ssh_config_dir)
              # Check directory permissions
              unless File.readable?(@ssh_config_dir) && File.writable?(@ssh_config_dir)
                errors << "sshconfigmanager.ssh_config_dir is not readable/writable: #{@ssh_config_dir}"
              end
            elsif @auto_create_dir
              begin
                # Try to create the directory to validate the path
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

        # Validate boolean options
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

        # Return validation results
        { 'SSH Config Manager' => errors }
      end

      # Get configuration summary for debugging
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

      # Check if the plugin should operate for a given action
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

      # Merge configuration from another config object (for inheritance)
      def merge(other)
        result = self.class.new

        # Merge each attribute, preferring the other config's values if set
        result.enabled = other.enabled != UNSET_VALUE ? other.enabled : @enabled
        result.ssh_config_dir = other.ssh_config_dir != UNSET_VALUE ? other.ssh_config_dir : @ssh_config_dir
        result.manage_includes = other.manage_includes != UNSET_VALUE ? other.manage_includes : @manage_includes
        result.auto_create_dir = other.auto_create_dir != UNSET_VALUE ? other.auto_create_dir : @auto_create_dir
        result.cleanup_empty_dir = other.cleanup_empty_dir != UNSET_VALUE ? other.cleanup_empty_dir : @cleanup_empty_dir
        result.auto_remove_on_destroy = other.auto_remove_on_destroy != UNSET_VALUE ? other.auto_remove_on_destroy : @auto_remove_on_destroy
        result.update_on_reload = other.update_on_reload != UNSET_VALUE ? other.update_on_reload : @update_on_reload
        result.refresh_on_provision = other.refresh_on_provision != UNSET_VALUE ? other.refresh_on_provision : @refresh_on_provision
        result.keep_config_on_halt = other.keep_config_on_halt != UNSET_VALUE ? other.keep_config_on_halt : @keep_config_on_halt
        result.project_isolation = other.project_isolation != UNSET_VALUE ? other.project_isolation : @project_isolation

        result
      end

      # Create SSH config directory with proper permissions
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

      # Get the appropriate manager instance
      def get_ssh_manager_instance(_machine)
        # Use separate file approach with FileManager
        require_relative 'file_manager'
        FileManager.new(self)
      end
    end
  end
end
