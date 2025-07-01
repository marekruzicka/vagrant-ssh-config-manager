require_relative '../ssh_config_manager'

module VagrantPlugins
  module SshConfigManager
    module Action
      class Destroy
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new("vagrant::plugins::ssh_config_manager::action::destroy")
        end

        def call(env)
          machine = env[:machine]
          
          # Handle SSH config removal before destroying the machine
          if machine
            config = machine.config.sshconfigmanager
            if config && config.enabled
              handle_ssh_config_removal(machine, config)
            end
          end

          # Call the next middleware (actual destroy)
          @app.call(env)
        end

        private

        def handle_ssh_config_removal(machine, config)
          begin
            @logger.info("Removing SSH config entry for machine: #{machine.name}")

            # Create SSH config manager
            manager = SshConfigManager.new(machine, config)
            
            # Generate the host name that was used
            host_name = manager.send(:generate_isolated_host_name, machine.name)

            # Check if SSH entry exists
            unless manager.ssh_entry_exists?(host_name)
              @logger.debug("No SSH config entry found for machine: #{machine.name}")
              return
            end

            # Remove SSH entry
            if manager.remove_ssh_entry(host_name)
              machine.ui.info("SSH config removed for machine '#{machine.name}' (#{host_name})")
            else
              machine.ui.warn("Failed to remove SSH config entry for machine: #{machine.name}")
            end

            # If this was the last machine in the project, clean up
            cleanup_project_if_empty(manager, machine)

          rescue => e
            @logger.error("Error removing SSH config for #{machine.name}: #{e.message}")
            @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
            
            # Don't fail the vagrant destroy process, just warn
            machine.ui.warn("SSH config manager encountered an error during cleanup: #{e.message}")
          end
        end

        def cleanup_project_if_empty(manager, machine)
          begin
            # Get all hosts for this project
            project_hosts = manager.get_project_hosts
            
            if project_hosts.empty?
              @logger.debug("No more hosts in project, cleaning up include file")
              manager.send(:cleanup_empty_include_file)
              manager.send(:cleanup_include_directive_if_needed)
              machine.ui.info("Project SSH config cleaned up (no more VMs)")
            else
              @logger.debug("Project still has #{project_hosts.length} hosts remaining")
            end
          rescue => e
            @logger.warn("Failed to cleanup empty project: #{e.message}")
          end
        end
      end
    end
  end
end
