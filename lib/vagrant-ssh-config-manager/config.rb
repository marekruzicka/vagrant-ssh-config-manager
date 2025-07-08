require 'fileutils'
require 'vagrant'

module VagrantPlugins
  module SshConfigManager
    class Config < Vagrant.plugin("2", :config)
      # Plugin enabled/disabled flag
      attr_accessor :enabled

      # Custom SSH config file path
      attr_accessor :ssh_conf_file

      # Separate file approach configuration
      attr_accessor :ssh_config_dir
      attr_accessor :manage_includes
      attr_accessor :auto_create_dir
      attr_accessor :cleanup_empty_dir

      # Additional configuration options
      attr_accessor :auto_remove_on_destroy
      attr_accessor :update_on_reload
      attr_accessor :refresh_on_provision
      attr_accessor :keep_config_on_halt
      attr_accessor :project_isolation

      def initialize
        @enabled = Vagrant::Plugin::V2::Config::UNSET_VALUE
        @ssh_conf_file = Vagrant::Plugin::V2::Config::UNSET_VALUE
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
        @ssh_conf_file = File.expand_path("~/.ssh/config") if @ssh_conf_file == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @ssh_config_dir = File.expand_path("~/.ssh/config.d/vagrant") if @ssh_config_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @manage_includes = false if @manage_includes == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @auto_create_dir = true if @auto_create_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @cleanup_empty_dir = true if @cleanup_empty_dir == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @auto_remove_on_destroy = true if @auto_remove_on_destroy == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @update_on_reload = true if @update_on_reload == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @refresh_on_provision = true if @refresh_on_provision == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @keep_config_on_halt = true if @keep_config_on_halt == Vagrant::Plugin::V2::Config::UNSET_VALUE
        @project_isolation = true if @project_isolation == Vagrant::Plugin::V2::Config::UNSET_VALUE

        # Expand and validate file paths
        @ssh_conf_file = File.expand_path(@ssh_conf_file) if @ssh_conf_file.is_a?(String)
        @ssh_config_dir = File.expand_path(@ssh_config_dir) if @ssh_config_dir.is_a?(String)
        
        # Ensure SSH config directory exists if auto_create_dir is enabled
        ensure_ssh_config_directory if @auto_create_dir && @ssh_config_dir
      end

      def validate(machine)
        errors = _detected_errors

        # Validate enabled flag
        unless [true, false].include?(@enabled)
          errors << "sshconfigmanager.enabled must be true or false"
        end

        # Validate SSH config file path
        if @ssh_conf_file
          unless @ssh_conf_file.is_a?(String)
            errors << "sshconfigmanager.ssh_conf_file must be a string path"
          else
            # Check if the parent directory exists or can be created
            ssh_dir = File.dirname(@ssh_conf_file)
            unless File.directory?(ssh_dir)
              begin
                # Try to create the directory to validate the path
                FileUtils.mkdir_p(ssh_dir, mode: 0700)
              rescue => e
                errors << "sshconfigmanager.ssh_conf_file directory cannot be created: #{e.message}"
              end
            end

            # Check if file exists and is writable, or if it can be created
            if File.exist?(@ssh_conf_file)
              unless File.writable?(@ssh_conf_file)
                errors << "sshconfigmanager.ssh_conf_file is not writable: #{@ssh_conf_file}"
              end
            else
              # Check if we can create the file
              begin
                File.write(@ssh_conf_file, "")
                File.delete(@ssh_conf_file)
              rescue => e
                errors << "sshconfigmanager.ssh_conf_file cannot be created: #{e.message}"
              end
            end
          end
        end

        # Validate SSH config directory
        if @ssh_config_dir
          unless @ssh_config_dir.is_a?(String)
            errors << "sshconfigmanager.ssh_config_dir must be a string path"
          else
            # Validate directory path format
            expanded_path = File.expand_path(@ssh_config_dir)
            if expanded_path.include?("..") || expanded_path.include?("//")
              errors << "sshconfigmanager.ssh_config_dir contains invalid path components: #{@ssh_config_dir}"
            end

            # Check if the directory exists or can be created
            unless File.directory?(@ssh_config_dir)
              if @auto_create_dir
                begin
                  # Try to create the directory to validate the path
                  FileUtils.mkdir_p(@ssh_config_dir, mode: 0700)
                rescue => e
                  errors << "sshconfigmanager.ssh_config_dir cannot be created: #{e.message}"
                end
              else
                errors << "sshconfigmanager.ssh_config_dir does not exist and auto_create_dir is disabled: #{@ssh_config_dir}"
              end
            else
              # Check directory permissions
              unless File.readable?(@ssh_config_dir) && File.writable?(@ssh_config_dir)
                errors << "sshconfigmanager.ssh_config_dir is not readable/writable: #{@ssh_config_dir}"
              end
            end
          end
        end

        # Check for configuration conflicts between legacy and new approaches
        if @ssh_conf_file != File.expand_path("~/.ssh/config") && @manage_includes
          errors << "sshconfigmanager.manage_includes cannot be enabled when using legacy ssh_conf_file option"
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
          unless [true, false].include?(value)
            errors << "sshconfigmanager.#{option_name} must be true or false"
          end
        end

        # Check for configuration conflicts between legacy and new approaches
        if has_configuration_conflicts?
          errors << "sshconfigmanager: Cannot use both legacy ssh_conf_file and new ssh_config_dir approaches simultaneously. Please choose one."
        end

        # Deprecation warning for legacy approach
        if using_legacy_approach?
          # Note: In a real plugin, this would use Vagrant's warning system
          # For now, we'll just add it to errors as a warning
          errors << "sshconfigmanager: WARNING - ssh_conf_file option is deprecated. Consider migrating to ssh_config_dir for better isolation."
        end

        # Return validation results
        { "SSH Config Manager" => errors }
      end

      # Get configuration summary for debugging
      def to_hash
        {
          enabled: @enabled,
          ssh_conf_file: @ssh_conf_file,
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

      # Get effective SSH config file path with validation
      def effective_ssh_config_file
        path = @ssh_conf_file || File.expand_path("~/.ssh/config")
        
        # Ensure directory exists
        ssh_dir = File.dirname(path)
        FileUtils.mkdir_p(ssh_dir, mode: 0700) unless File.directory?(ssh_dir)
        
        path
      end

      # Merge configuration from another config object (for inheritance)
      def merge(other)
        result = self.class.new

        # Merge each attribute, preferring the other config's values if set
        result.enabled = other.enabled != UNSET_VALUE ? other.enabled : @enabled
        result.ssh_conf_file = other.ssh_conf_file != UNSET_VALUE ? other.ssh_conf_file : @ssh_conf_file
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
          FileUtils.mkdir_p(@ssh_config_dir, mode: 0700)
          true
        rescue => e
          false
        end
      end

      # Check if using legacy configuration approach
      def using_legacy_approach?
        @ssh_conf_file != Vagrant::Plugin::V2::Config::UNSET_VALUE && 
        @ssh_conf_file != File.expand_path("~/.ssh/config")
      end

      # Check if using new separate file approach
      def using_separate_file_approach?
        @ssh_config_dir != Vagrant::Plugin::V2::Config::UNSET_VALUE && 
        @ssh_config_dir != File.expand_path("~/.ssh/config.d/vagrant")
      end

      # Detect configuration conflicts
      def has_configuration_conflicts?
        using_legacy_approach? && using_separate_file_approach?
      end

      # Get effective approach (legacy or separate files)
      def effective_approach
        if has_configuration_conflicts?
          :conflict
        elsif using_legacy_approach?
          :legacy
        else
          :separate_files
        end
      end

      # Migrate from legacy to new approach
      def migrate_to_separate_files(force: false)
        return false unless using_legacy_approach?
        return false if using_separate_file_approach? && !force
        
        # Set new approach configuration
        @ssh_config_dir = File.expand_path("~/.ssh/config.d/vagrant")
        @manage_includes = true
        
        # Reset legacy configuration if forced
        if force
          @ssh_conf_file = File.expand_path("~/.ssh/config")
        end
        
        true
      end

      # Migrate from legacy configuration to new approach
      def migrate_to_separate_files!
        return false unless using_legacy_mode?
        
        # Set new approach defaults
        @ssh_config_dir = File.expand_path("~/.ssh/config.d/vagrant")
        @manage_includes = true
        @auto_create_dir = true
        @cleanup_empty_dir = true
        
        # Reset ssh_conf_file to default if it was the only legacy setting
        if @ssh_conf_file == File.expand_path("~/.ssh/config")
          # Already at default, just enable new features
        end
        
        true
      end

      # Check if migration is recommended
      def migration_recommended?
        using_legacy_approach? && !using_separate_file_approach?
      end

      # Check if using legacy configuration
      def using_legacy_mode?
        # Legacy mode if ssh_conf_file is explicitly set and ssh_config_dir is default
        @ssh_conf_file != File.expand_path("~/.ssh/config") ||
        (!@manage_includes && @ssh_config_dir == File.expand_path("~/.ssh/config.d/vagrant"))
      end

      # Get the appropriate manager instance based on configuration mode
      def get_ssh_manager_instance(machine)
        if using_legacy_mode?
          # Use legacy SSH config manager
          require_relative 'ssh_config_manager'
          SshConfigManager.new(machine, self)
        else
          # Use new separate file approach
          require_relative 'file_manager'
          FileManager.new(self)
        end
      end

      # Check for legacy configuration warnings
      def legacy_warnings
        warnings = []
        
        if @ssh_conf_file != File.expand_path("~/.ssh/config")
          warnings << "Using legacy ssh_conf_file option. Consider migrating to the new separate files approach with ssh_config_dir."
        end
        
        warnings
      end

      # Get migration recommendations
      def migration_recommendations
        return [] unless using_legacy_mode?
        
        recommendations = []
        recommendations << "Consider enabling manage_includes for automatic Include directive management"
        recommendations << "The new separate files approach provides better VM isolation"
        recommendations << "Automatic cleanup prevents SSH config pollution"
        
        recommendations
      end
    end
  end
end
