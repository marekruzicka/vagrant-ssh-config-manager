# frozen_string_literal: true

module VagrantPlugins
  module SshConfigManager
    module Action
      class Provision
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new('vagrant::plugins::ssh_config_manager::action::provision')
        end

        def call(env)
          # Call the next middleware first (actual provisioning)
          @app.call(env)

          # Only proceed if the machine is running and SSH is ready
          machine = env[:machine]
          return unless machine && machine.state.id == :running

          # Check if plugin is enabled
          config = machine.config.sshconfigmanager
          return unless config&.enabled && config.refresh_on_provision

          # Handle SSH config file refresh after provisioning
          handle_ssh_config_refresh(machine, config)
        end

        private

        def handle_ssh_config_refresh(machine, config)
          @logger.info("Refreshing SSH config file after provisioning for machine: #{machine.name}")

          # Lazy load required classes with error handling
          begin
            require 'vagrant_ssh_config_manager/ssh_info_extractor'
            require 'vagrant_ssh_config_manager/file_manager'
            require 'vagrant_ssh_config_manager/include_manager'
          rescue LoadError => e
            @logger.error("Failed to load required classes: #{e.message}")
            machine.ui.warn('SSH config manager: Failed to load required components, skipping SSH config refresh')
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

          # Refresh SSH config file (regenerate it)
          # Provisioning might have changed SSH configuration
          if file_manager.write_ssh_config_file(machine)
            file_manager.send(:generate_host_name, machine)
            machine.ui.info("SSH config file refreshed for machine '#{machine.name}' after provisioning")
            @logger.info('SSH config file refreshed due to provisioning')

            # Ensure Include directive is managed
            include_manager.manage_include_directive
          else
            machine.ui.warn("Failed to refresh SSH config file for machine: #{machine.name}")
            @logger.warn("Failed to refresh SSH config file for #{machine.name}")
          end
        rescue StandardError => e
          @logger.error("Error refreshing SSH config for #{machine.name}: #{e.message}")
          @logger.debug("Backtrace: #{e.backtrace.join("\n")}")

          # Don't fail the vagrant provision process, just warn
          machine.ui.warn("SSH config manager encountered an error during refresh: #{e.message}")
        end
      end
    end
  end
end
