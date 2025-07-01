require_relative '../ssh_info_extractor'
require_relative '../ssh_config_manager'

module VagrantPlugins
  module SshConfigManager
    module Action
      class Reload
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new("vagrant::plugins::ssh_config_manager::action::reload")
        end

        def call(env)
          # Call the next middleware first
          @app.call(env)

          # Only proceed if the machine is running and SSH is ready
          machine = env[:machine]
          return unless machine && machine.state.id == :running

          # Check if plugin is enabled
          config = machine.config.sshconfigmanager
          return unless config && config.enabled

          # Handle SSH config update
          handle_ssh_config_update(machine, config)
        end

        private

        def handle_ssh_config_update(machine, config)
          begin
            @logger.info("Updating SSH config entry for machine: #{machine.name}")

            # Extract SSH information
            extractor = SshInfoExtractor.new(machine)
            
            # Check if machine supports SSH
            unless extractor.ssh_capable?
              @logger.debug("Machine #{machine.name} does not support SSH, skipping")
              return
            end

            ssh_info = extractor.extract_ssh_info
            unless ssh_info
              @logger.warn("Could not extract SSH info for machine: #{machine.name}")
              return
            end

            # Generate unique host name for project isolation
            manager = SshConfigManager.new(machine, config)
            host_name = manager.send(:generate_isolated_host_name, machine.name)
            ssh_info['Host'] = host_name

            # Check if entry exists and compare
            if manager.ssh_entry_exists?(host_name)
              # Get existing entry for comparison
              existing_entries = manager.get_project_ssh_entries
              existing_entry = existing_entries.find { |entry| entry['Host'] == host_name }
              
              if existing_entry && ssh_configs_different?(existing_entry, ssh_info)
                # Update SSH entry
                if manager.update_ssh_entry(ssh_info)
                  machine.ui.info("SSH config updated for machine '#{machine.name}' (#{host_name})")
                  @logger.info("SSH config updated due to changes in network configuration")
                else
                  machine.ui.warn("Failed to update SSH config entry for machine: #{machine.name}")
                end
              else
                @logger.debug("SSH config unchanged for machine: #{machine.name}")
              end
            else
              # Add new SSH entry (machine might have been added during reload)
              if manager.add_ssh_entry(ssh_info)
                machine.ui.info("SSH config added for machine '#{machine.name}' as '#{host_name}'")
              else
                machine.ui.warn("Failed to add SSH config entry for machine: #{machine.name}")
              end
            end

          rescue => e
            @logger.error("Error updating SSH config for #{machine.name}: #{e.message}")
            @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
            
            # Don't fail the vagrant reload process, just warn
            machine.ui.warn("SSH config manager encountered an error: #{e.message}")
          end
        end

        def ssh_configs_different?(existing, new_config)
          # Compare key SSH configuration parameters
          important_keys = %w[HostName Port User IdentityFile ProxyCommand]
          
          important_keys.any? do |key|
            existing[key] != new_config[key]
          end
        end
      end
    end
  end
end
