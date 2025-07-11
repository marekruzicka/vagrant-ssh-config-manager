# frozen_string_literal: true

module VagrantPlugins
  module SshConfigManager
    module Action
      class Up
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new('vagrant::plugins::ssh_config_manager::action::up')
        end

        def call(env)
          # Call the next middleware first
          @app.call(env)

          # Only proceed if the machine is running and SSH is ready
          machine = env[:machine]
          return unless machine
          return unless machine.state.id == :running

          # Check if plugin is enabled
          config = machine.config.sshconfigmanager
          return unless config&.enabled

          @logger.info("SSH Config Manager: Creating SSH config file for machine: #{machine.name}")

          # Handle SSH config file creation
          handle_ssh_config_creation(machine, config)
        rescue StandardError => e
          @logger.error("SSH Config Manager: Error in Up action: #{e.message}")
          @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
        end

        private

        def handle_ssh_config_creation(machine, config)
          @logger.info("Creating SSH config file for machine: #{machine.name}")

          # Lazy load required classes with error handling
          begin
            require 'vagrant_ssh_config_manager/ssh_info_extractor'
            require 'vagrant_ssh_config_manager/file_manager'
            require 'vagrant_ssh_config_manager/include_manager'
          rescue LoadError => e
            @logger.error("Failed to load required classes: #{e.message}")
            machine.ui.warn('SSH config manager: Failed to load required components, skipping SSH config creation')
            return
          end

          # Extract SSH information
          extractor = SshInfoExtractor.new(machine)

          # Check if machine supports SSH
          unless extractor.ssh_capable?
            @logger.debug("Machine #{machine.name} does not support SSH, skipping")
            return
          end

          # Create file manager and include manager
          file_manager = FileManager.new(config)
          include_manager = IncludeManager.new(config)

          # Write SSH config file
          @logger.info("Attempting to create SSH config file for #{machine.name}")

          if file_manager.write_ssh_config_file(machine)
            host_name = file_manager.send(:generate_host_name, machine)
            machine.ui.info("SSH config file created for machine '#{machine.name}' as '#{host_name}'")
            machine.ui.info("You can now connect with: ssh #{host_name}")
            @logger.info("Successfully created SSH config file for #{machine.name}")

            # Manage Include directive after file creation
            include_manager.manage_include_directive
          else
            machine.ui.warn("Failed to create SSH config file for machine: #{machine.name}")
            @logger.warn("Failed to create SSH config file for #{machine.name}")
          end
        rescue Errno::EACCES => e
          @logger.error("Permission denied accessing SSH config for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: Permission denied. Check file permissions.')
        rescue Errno::ENOSPC => e
          @logger.error("No space left on device for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: No space left on device.')
        rescue Errno::EIO => e
          @logger.error("I/O error for #{machine.name}: #{e.message}")
          machine.ui.warn('SSH config manager: I/O error accessing SSH config files.')
        rescue StandardError => e
          @logger.error("Error creating SSH config for #{machine.name}: #{e.message}")
          @logger.debug("Backtrace: #{e.backtrace.join("\n")}")

          # Don't fail the vagrant up process, just warn
          machine.ui.warn("SSH config manager encountered an error: #{e.message}")
        end
      end
    end
  end
end
