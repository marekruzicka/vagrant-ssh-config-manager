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

            # Check file permissions before attempting operations
            check_file_permissions(machine, config)

            # Extract SSH information
            extractor = SshInfoExtractor.new(machine)
            
            # Check if machine supports SSH
            unless extractor.ssh_capable?
              @logger.debug("Machine #{machine.name} does not support SSH, skipping")
              machine.ui.info("Machine #{machine.name} does not support SSH, skipping SSH config update")
              return
            end

            ssh_info = extractor.extract_ssh_info
            unless ssh_info
              @logger.warn("Could not extract SSH info for machine: #{machine.name}")
              machine.ui.warn("Could not extract SSH info for machine: #{machine.name}")
              return
            end

            # Generate unique host name for project isolation
            manager = SshConfigManager.new(machine, config)
            host_name = manager.send(:generate_isolated_host_name, machine.name)
            ssh_info['Host'] = host_name

            @logger.info("Checking SSH config changes for #{machine.name} (#{host_name})")

            # Check if entry exists and compare
            if manager.ssh_entry_exists?(host_name)
              # Get existing entry for comparison
              existing_entries = manager.get_project_ssh_entries
              existing_entry = existing_entries.find { |entry| entry['Host'] == host_name }
              
              if existing_entry && ssh_configs_different?(existing_entry, ssh_info)
                # Update SSH entry
                @logger.info("SSH config changes detected, updating entry for #{machine.name}")
                if manager.update_ssh_entry(ssh_info)
                  machine.ui.info("SSH config updated for machine '#{machine.name}' (#{host_name})")
                  @logger.info("SSH config updated due to changes in network configuration")
                else
                  machine.ui.warn("Failed to update SSH config entry for machine: #{machine.name}")
                  @logger.warn("Failed to update SSH config entry for #{machine.name}")
                end
              else
                @logger.debug("SSH config unchanged for machine: #{machine.name}")
                machine.ui.info("SSH config unchanged for machine: #{machine.name}")
              end
            else
              # Add new SSH entry (machine might have been added during reload)
              @logger.info("No existing SSH config entry found, adding new entry for #{machine.name}")
              if manager.add_ssh_entry(ssh_info)
                machine.ui.info("SSH config added for machine '#{machine.name}' as '#{host_name}'")
                @logger.info("Successfully added new SSH config entry for #{machine.name}")
              else
                machine.ui.warn("Failed to add SSH config entry for machine: #{machine.name}")
                @logger.warn("Failed to add SSH config entry for #{machine.name}")
              end
            end

          rescue Errno::EACCES => e
            @logger.error("Permission denied accessing SSH config file for #{machine.name}: #{e.message}")
            machine.ui.warn("SSH config manager: Permission denied. Check file permissions.")
          rescue Errno::EIO => e
            @logger.error("I/O error for #{machine.name}: #{e.message}")
            machine.ui.warn("SSH config manager: I/O error accessing SSH config file.")
          rescue => e
            @logger.error("Error updating SSH config for #{machine.name}: #{e.message}")
            @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
            
            # Don't fail the vagrant reload process, just warn
            machine.ui.warn("SSH config manager encountered an error: #{e.message}")
          end
        end

        def check_file_permissions(machine, config)
          ssh_config_file = config.ssh_conf_file || File.expand_path("~/.ssh/config")
          
          if File.exist?(ssh_config_file)
            unless File.writable?(ssh_config_file)
              @logger.warn("SSH config file is not writable: #{ssh_config_file}")
              machine.ui.warn("Warning: SSH config file is not writable: #{ssh_config_file}")
            end
          else
            ssh_dir = File.dirname(ssh_config_file)
            unless File.writable?(ssh_dir)
              @logger.warn("SSH directory is not writable: #{ssh_dir}")
              machine.ui.warn("Warning: SSH directory is not writable: #{ssh_dir}")
            end
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
