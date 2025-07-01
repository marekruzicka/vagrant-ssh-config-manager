require_relative '../ssh_info_extractor'
require_relative '../ssh_config_manager'

module VagrantPlugins
  module SshConfigManager
    module Action
      class Up
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new("vagrant::plugins::ssh_config_manager::action::up")
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

          # Handle SSH config addition
          handle_ssh_config_addition(machine, config)
        end

        private

        def handle_ssh_config_addition(machine, config)
          begin
            @logger.info("Adding SSH config entry for machine: #{machine.name}")

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

            # Check if SSH config file is writable
            check_file_permissions(machine, config)

            # Add SSH entry with enhanced logging
            @logger.info("Attempting to add SSH config entry for #{machine.name} as #{host_name}")
            
            if manager.add_ssh_entry(ssh_info)
              machine.ui.info("SSH config added for machine '#{machine.name}' as '#{host_name}'")
              machine.ui.info("You can now connect with: ssh #{host_name}")
              @logger.info("Successfully added SSH config entry for #{machine.name}")
            else
              machine.ui.warn("Failed to add SSH config entry for machine: #{machine.name}")
              @logger.warn("Failed to add SSH config entry for #{machine.name}")
            end

          rescue Errno::EACCES => e
            @logger.error("Permission denied accessing SSH config file for #{machine.name}: #{e.message}")
            machine.ui.warn("SSH config manager: Permission denied. Check file permissions.")
          rescue Errno::ENOSPC => e
            @logger.error("No space left on device for #{machine.name}: #{e.message}")
            machine.ui.warn("SSH config manager: No space left on device.")
          rescue Errno::EIO => e
            @logger.error("I/O error for #{machine.name}: #{e.message}")
            machine.ui.warn("SSH config manager: I/O error accessing SSH config file.")
          rescue => e
            @logger.error("Error adding SSH config for #{machine.name}: #{e.message}")
            @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
            
            # Don't fail the vagrant up process, just warn
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
      end
    end
  end
end
