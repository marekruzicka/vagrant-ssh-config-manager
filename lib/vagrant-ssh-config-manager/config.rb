require 'fileutils'

module VagrantPlugins
  module SshConfigManager
    class Config < Vagrant.plugin("2", :config)
      # Plugin enabled/disabled flag
      attr_accessor :enabled

      # Custom SSH config file path
      attr_accessor :ssh_conf_file

      # Additional configuration options
      attr_accessor :auto_remove_on_destroy
      attr_accessor :update_on_reload
      attr_accessor :refresh_on_provision
      attr_accessor :keep_config_on_halt
      attr_accessor :project_isolation

      def initialize
        @enabled = UNSET_VALUE
        @ssh_conf_file = UNSET_VALUE
        @auto_remove_on_destroy = UNSET_VALUE
        @update_on_reload = UNSET_VALUE
        @refresh_on_provision = UNSET_VALUE
        @keep_config_on_halt = UNSET_VALUE
        @project_isolation = UNSET_VALUE
      end

      def finalize!
        # Set default values for unset configuration options
        @enabled = true if @enabled == UNSET_VALUE
        @ssh_conf_file = File.expand_path("~/.ssh/config") if @ssh_conf_file == UNSET_VALUE
        @auto_remove_on_destroy = true if @auto_remove_on_destroy == UNSET_VALUE
        @update_on_reload = true if @update_on_reload == UNSET_VALUE
        @refresh_on_provision = true if @refresh_on_provision == UNSET_VALUE
        @keep_config_on_halt = true if @keep_config_on_halt == UNSET_VALUE
        @project_isolation = true if @project_isolation == UNSET_VALUE

        # Expand file paths
        @ssh_conf_file = File.expand_path(@ssh_conf_file) if @ssh_conf_file.is_a?(String)
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

        # Validate boolean options
        boolean_options = {
          'auto_remove_on_destroy' => @auto_remove_on_destroy,
          'update_on_reload' => @update_on_reload,
          'refresh_on_provision' => @refresh_on_provision,
          'keep_config_on_halt' => @keep_config_on_halt,
          'project_isolation' => @project_isolation
        }

        boolean_options.each do |option_name, value|
          unless [true, false].include?(value)
            errors << "sshconfigmanager.#{option_name} must be true or false"
          end
        end

        # Return validation results
        { "SSH Config Manager" => errors }
      end

      # Get configuration summary for debugging
      def to_hash
        {
          enabled: @enabled,
          ssh_conf_file: @ssh_conf_file,
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
        result.auto_remove_on_destroy = other.auto_remove_on_destroy != UNSET_VALUE ? other.auto_remove_on_destroy : @auto_remove_on_destroy
        result.update_on_reload = other.update_on_reload != UNSET_VALUE ? other.update_on_reload : @update_on_reload
        result.refresh_on_provision = other.refresh_on_provision != UNSET_VALUE ? other.refresh_on_provision : @refresh_on_provision
        result.keep_config_on_halt = other.keep_config_on_halt != UNSET_VALUE ? other.keep_config_on_halt : @keep_config_on_halt
        result.project_isolation = other.project_isolation != UNSET_VALUE ? other.project_isolation : @project_isolation

        result
      end
    end
  end
end
