# frozen_string_literal: true

module VagrantPlugins
  module SshConfigManager
    module Action
      # Handles SSH config cleanup when a Vagrant machine is destroyed
      class Destroy
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new('vagrant::plugins::ssh_config_manager::action::destroy')
        end

        def call(env)
          machine = env[:machine]

          # Handle SSH config removal before destroying the machine
          if machine
            config = machine.config.sshconfigmanager
            handle_ssh_config_removal(machine, config) if config&.enabled && config.auto_remove_on_destroy
          end

          # Call the next middleware (actual destroy)
          @app.call(env)
        end

        private

        def handle_ssh_config_removal(machine, config)
          @logger.info("Removing SSH config file for machine: #{machine.name}")

          # Lazy load required classes with error handling
          begin
            require 'vagrant_ssh_config_manager/file_manager'
            require 'vagrant_ssh_config_manager/include_manager'
          rescue LoadError => e
            @logger.error("Failed to load required classes: #{e.message}")
            machine.ui.warn('SSH config manager: Failed to load required components, skipping SSH config removal')
            return
          end

          # Create file manager and include manager
          file_manager = FileManager.new(config)
          include_manager = IncludeManager.new(config)

          # Check if SSH config file exists
          unless file_manager.ssh_config_file_exists?(machine)
            @logger.debug("No SSH config file found for machine: #{machine.name}")
            machine.ui.info("No SSH config file found to remove for machine: #{machine.name}")
            return
          end

          # Remove SSH config file with logging
          @logger.info("Attempting to remove SSH config file for #{machine.name}")

          if file_manager.remove_ssh_config_file(machine)
            machine.ui.info("SSH config file removed for machine '#{machine.name}'")
            @logger.info("Successfully removed SSH config file for #{machine.name}")

            # Manage Include directive after file removal
            include_manager.manage_include_directive
          else
            machine.ui.warn("Failed to remove SSH config file for machine: #{machine.name}")
            @logger.warn("Failed to remove SSH config file for #{machine.name}")
          end
        rescue Errno::EACCES => e
          @logger.error("Permission denied accessing SSH config for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: Permission denied. Check file permissions.')
        rescue Errno::EIO => e
          @logger.error("I/O error for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: I/O error accessing SSH config files.')
        rescue StandardError => e
          @logger.error("Error removing SSH config for #{machine.name}: #{e.message}")
          @logger.debug("Backtrace: #{e.backtrace.join("\n")}")

          # Don't fail the vagrant destroy process, just warn
          machine.ui.warn("SSH config manager encountered an error during cleanup: #{e.message}")
        end
      end
    end
  end
end
