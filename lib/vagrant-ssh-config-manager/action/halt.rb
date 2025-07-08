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
            if config && config.enabled && config.keep_config_on_halt
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

            # With separate files, we keep the SSH config file during halt/suspend
            # This allows users to quickly resume and reconnect
            case operation
            when :halt, :suspend, :poweroff, :force_halt
              machine.ui.info("Machine #{operation}ed - SSH config file retained")
              @logger.debug("Keeping SSH config file for #{operation}ed machine: #{machine.name}")
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
      end
    end
  end
end
