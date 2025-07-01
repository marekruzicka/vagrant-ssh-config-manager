require_relative '../ssh_config_manager'

module VagrantPlugins
  module SshConfigManager
    module Action
      class Halt
        def initialize(app, env)
          @app = app
          @env = env
          @logger = Log4r::Logger.new("vagrant::plugins::ssh_config_manager::action::halt")
        end

        def call(env)
          machine = env[:machine]
          
          # Handle SSH config for halt/suspend operations
          if machine
            config = machine.config.sshconfigmanager
            if config && config.enabled
              handle_ssh_config_for_halt(machine, config, env)
            end
          end

          # Call the next middleware (actual halt/suspend)
          @app.call(env)
        end

        private

        def handle_ssh_config_for_halt(machine, config, env)
          begin
            # Determine the type of operation
            operation = determine_operation_type(env)
            @logger.info("Handling SSH config for #{operation} operation on machine: #{machine.name}")

            manager = SshConfigManager.new(machine, config)
            host_name = manager.send(:generate_isolated_host_name, machine.name)

            case operation
            when :halt, :suspend
              # For halt/suspend, we can keep the SSH config but add a note that it's offline
              # This way users can still see the configuration and quickly resume
              handle_offline_state(machine, manager, host_name, operation)
            when :poweroff, :force_halt
              # For forced operations, also keep config but mark as offline
              handle_offline_state(machine, manager, host_name, operation)
            else
              @logger.debug("No SSH config action needed for operation: #{operation}")
            end

          rescue => e
            @logger.error("Error handling SSH config for halt/suspend #{machine.name}: #{e.message}")
            @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
            
            # Don't fail the halt/suspend process
            machine.ui.warn("SSH config manager encountered an error: #{e.message}")
          end
        end

        def determine_operation_type(env)
          # Try to determine what type of halt operation this is
          if env[:force_halt]
            :force_halt
          elsif env[:suspend]
            :suspend
          elsif env[:graceful_halt] == false
            :poweroff
          else
            :halt
          end
        end

        def handle_offline_state(machine, manager, host_name, operation)
          # Check if SSH entry exists
          unless manager.ssh_entry_exists?(host_name)
            @logger.debug("No SSH config entry found for machine: #{machine.name}")
            return
          end

          # For now, we keep the SSH config entries even when machines are halted/suspended
          # This allows users to quickly resume and reconnect
          # In the future, we could add a configuration option to remove entries on halt

          case operation
          when :halt
            machine.ui.info("Machine halted - SSH config retained for '#{host_name}'")
            @logger.debug("Keeping SSH config for halted machine: #{machine.name}")
          when :suspend
            machine.ui.info("Machine suspended - SSH config retained for '#{host_name}'")
            @logger.debug("Keeping SSH config for suspended machine: #{machine.name}")
          when :poweroff, :force_halt
            machine.ui.info("Machine powered off - SSH config retained for '#{host_name}'")
            @logger.debug("Keeping SSH config for powered off machine: #{machine.name}")
          end

          # Optional: Add metadata to track machine state
          # This could be useful for future features like showing machine status in SSH config
          update_machine_state_metadata(manager, host_name, operation)
        end

        def update_machine_state_metadata(manager, host_name, operation)
          # This is a placeholder for potential future functionality
          # We could add comments to the SSH config indicating machine state
          # For now, we just log the state change
          @logger.debug("Machine #{host_name} transitioned to state: #{operation}")
        end
      end
    end
  end
end
