require_relative '../ssh_info_extractor'
require_relative '../ssh_config_manager'

module VagrantPlugins
  module SshConfigManager
    module Action
      class Provision
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new("vagrant::plugins::ssh_config_manager::action::provision")
        end

        def call(env)
          # Call the next middleware first (actual provisioning)
          @app.call(env)

          # Only proceed if the machine is running and SSH is ready
          machine = env[:machine]
          return unless machine && machine.state.id == :running

          # Check if plugin is enabled
          config = machine.config.sshconfigmanager
          return unless config && config.enabled

          # Handle SSH config refresh after provisioning
          handle_ssh_config_refresh(machine, config)
        end

        private

        def handle_ssh_config_refresh(machine, config)
          begin
            @logger.info("Refreshing SSH config entry after provisioning for machine: #{machine.name}")

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

            # Check if we need to refresh the SSH config
            refresh_needed = check_if_refresh_needed(machine, manager, host_name, ssh_info)

            if refresh_needed
              # Update SSH entry
              if manager.update_ssh_entry(ssh_info)
                machine.ui.info("SSH config refreshed for machine '#{machine.name}' after provisioning")
                @logger.info("SSH config refreshed due to provisioning changes")
              else
                machine.ui.warn("Failed to refresh SSH config entry for machine: #{machine.name}")
              end
            else
              @logger.debug("SSH config refresh not needed for machine: #{machine.name}")
            end

          rescue => e
            @logger.error("Error refreshing SSH config for #{machine.name}: #{e.message}")
            @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
            
            # Don't fail the vagrant provision process, just warn
            machine.ui.warn("SSH config manager encountered an error during refresh: #{e.message}")
          end
        end

        def check_if_refresh_needed(machine, manager, host_name, new_ssh_info)
          # Always refresh after provisioning as network configuration might have changed
          # Provisioning could involve:
          # - Installing new SSH keys
          # - Changing SSH daemon configuration
          # - Modifying network settings
          # - Adding/removing users
          # - Changing firewall rules that affect SSH

          # Check if entry exists
          unless manager.ssh_entry_exists?(host_name)
            @logger.info("SSH entry doesn't exist, will be created")
            return true
          end

          # Get existing entry for comparison
          existing_entries = manager.get_project_ssh_entries
          existing_entry = existing_entries.find { |entry| entry['Host'] == host_name }
          
          unless existing_entry
            @logger.info("Could not find existing SSH entry, will refresh")
            return true
          end

          # Check for differences in critical SSH parameters
          if ssh_configs_different?(existing_entry, new_ssh_info)
            @logger.info("SSH configuration changes detected, refresh needed")
            return true
          end

          # Check if provisioning might have affected SSH
          if provisioning_affects_ssh?(machine)
            @logger.info("Provisioning might have affected SSH, refreshing as precaution")
            return true
          end

          false
        end

        def ssh_configs_different?(existing, new_config)
          # Compare key SSH configuration parameters that might change during provisioning
          important_keys = %w[HostName Port User IdentityFile ProxyCommand StrictHostKeyChecking UserKnownHostsFile]
          
          important_keys.any? do |key|
            existing_value = existing[key]
            new_value = new_config[key]
            
            # Normalize values for comparison
            existing_value = existing_value.to_s.strip if existing_value
            new_value = new_value.to_s.strip if new_value
            
            existing_value != new_value
          end
        end

        def provisioning_affects_ssh?(machine)
          # Heuristics to determine if provisioning might have affected SSH
          # This is conservative - when in doubt, refresh
          
          begin
            # Check if any provisioners might affect SSH
            machine.config.vm.provisioners.each do |provisioner|
              case provisioner.type
              when :shell
                # Shell provisioners might change SSH configuration
                return true if provisioner.config.path&.include?('ssh') || 
                              provisioner.config.inline&.include?('ssh')
              when :ansible, :ansible_local
                # Ansible often configures SSH
                return true
              when :puppet, :chef
                # Configuration management tools often manage SSH
                return true
              when :docker
                # Docker provisioning might affect networking
                return true
              end
            end
            
            # If we can't determine, err on the side of caution
            true
          rescue => e
            @logger.debug("Error checking provisioner types: #{e.message}")
            # If we can't check, assume provisioning might affect SSH
            true
          end
        end
      end
    end
  end
end
