# frozen_string_literal: true

module VagrantPlugins
  module SshConfigManager
    module Action
      class Reload
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new('vagrant::plugins::ssh_config_manager::action::reload')
        end

        def call(env)
          # Call the next middleware first
          @app.call(env)

          # Only proceed if the machine is running and SSH is ready
          machine = env[:machine]
          return unless machine && machine.state.id == :running

          # Check if plugin is enabled
          config = machine.config.sshconfigmanager
          return unless config&.enabled

          # Handle SSH config update
          handle_ssh_config_update(machine, config)
        end

        private

        def handle_ssh_config_update(machine, config)
          @logger.info("Updating SSH config entry for machine: #{machine.name}")

          # Lazy load required classes with error handling
          begin
            require 'vagrant_ssh_config_manager/ssh_info_extractor'
            require 'vagrant_ssh_config_manager/file_manager'
            require 'vagrant_ssh_config_manager/include_manager'
          rescue LoadError => e
            @logger.error("Failed to load required classes: #{e.message}")
            machine.ui.warn('SSH config manager: Failed to load required components, skipping SSH config update')
            return
          end

          # Extract SSH information
          extractor = SshInfoExtractor.new(machine)

          # Check if machine supports SSH
          unless extractor.ssh_capable?
            @logger.debug("Machine #{machine.name} does not support SSH, skipping")
            machine.ui.info("Machine #{machine.name} does not support SSH, skipping SSH config update")
            return
          end

          # Create file manager and include manager
          file_manager = FileManager.new(config)
          include_manager = IncludeManager.new(config)

          # Check if file exists and compare content
          if file_manager.ssh_config_file_exists?(machine)
            # Update SSH config file (always regenerate for simplicity)
            @logger.info("SSH config file exists, updating for #{machine.name}")
            if file_manager.write_ssh_config_file(machine)
              host_name = file_manager.send(:generate_host_name, machine)
              machine.ui.info("SSH config file updated for machine '#{machine.name}' (#{host_name})")
              @logger.info('SSH config file updated due to reload')

              # Ensure Include directive is managed
              include_manager.manage_include_directive
            else
              machine.ui.warn("Failed to update SSH config file for machine: #{machine.name}")
              @logger.warn("Failed to update SSH config file for #{machine.name}")
            end
          else
            # Add new SSH config file (machine might have been added during reload)
            @logger.info("No existing SSH config file found, creating new file for #{machine.name}")
            if file_manager.write_ssh_config_file(machine)
              host_name = file_manager.send(:generate_host_name, machine)
              machine.ui.info("SSH config file created for machine '#{machine.name}' as '#{host_name}'")
              @logger.info("Successfully created new SSH config file for #{machine.name}")

              # Manage Include directive after file creation
              include_manager.manage_include_directive
            else
              machine.ui.warn("Failed to create SSH config file for machine: #{machine.name}")
              @logger.warn("Failed to create SSH config file for #{machine.name}")
            end
          end
        rescue Errno::EACCES => e
          @logger.error("Permission denied accessing SSH config for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: Permission denied. Check file permissions.')
        rescue Errno::EIO => e
          @logger.error("I/O error for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: I/O error accessing SSH config files.')
        rescue StandardError => e
          @logger.error("Error updating SSH config for #{machine.name}: #{e.message}")
          @logger.debug("Backtrace: #{e.backtrace.join("\n")}")

          # Don't fail the vagrant reload process, just warn
          machine.ui.warn("SSH config manager encountered an error: #{e.message}")
        end
      end
    end
  end
end
