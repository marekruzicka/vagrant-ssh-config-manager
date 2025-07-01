module VagrantPlugins
  module SshConfigManager
    class SshInfoExtractor
      def initialize(machine)
        @machine = machine
        @logger = Log4r::Logger.new("vagrant::plugins::ssh_config_manager::ssh_info_extractor")
      end

      # Extract SSH information from Vagrant's internal APIs
      # This replicates what 'vagrant ssh-config' does but using internal methods
      def extract_ssh_info
        # Handle edge cases for non-SSH-capable boxes
        return nil unless machine_supports_ssh?
        
        begin
          ssh_info = @machine.ssh_info
          return nil if ssh_info.nil?

          # Additional validation for SSH info completeness
          return nil unless valid_ssh_info?(ssh_info)

          # Get the SSH configuration similar to what vagrant ssh-config provides
          config = build_ssh_config(ssh_info)
          
          @logger.info("Extracted SSH info for machine: #{@machine.name}")
          config
        rescue Vagrant::Errors::SSHNotReady => e
          @logger.debug("SSH not ready for machine #{@machine.name}: #{e.message}")
          nil
        rescue Vagrant::Errors::SSHUnavailable => e
          @logger.debug("SSH unavailable for machine #{@machine.name}: #{e.message}")
          nil
        rescue => e
          @logger.warn("Failed to extract SSH info for machine #{@machine.name}: #{e.message}")
          nil
        end
      end

      # Check if the machine supports SSH with comprehensive validation
      def ssh_capable?
        machine_supports_ssh? && valid_ssh_info?(@machine.ssh_info) rescue false
      end

      # Comprehensive check for SSH support
      def machine_supports_ssh?
        # Basic checks
        return false unless @machine
        return false unless @machine.communicate_ready?
        
        # Check if machine state supports SSH
        return false unless machine_state_supports_ssh?
        
        # Check if communicator is SSH-based
        return false unless ssh_communicator?
        
        # Check if provider supports SSH
        return false unless provider_supports_ssh?
        
        true
      rescue => e
        @logger.debug("Machine SSH support check failed: #{e.message}")
        false
      end

      private

      # Check if machine state allows SSH connections
      def machine_state_supports_ssh?
        state = @machine.state
        return false unless state
        
        # Common states that support SSH
        ssh_ready_states = [:running, :up, :active, :created]
        ssh_ready_states.include?(state.id)
      rescue
        false
      end

      # Check if the communicator is SSH-based
      def ssh_communicator?
        communicator = @machine.config.vm.communicator
        communicator.nil? || communicator == :ssh
      rescue
        # Default to assuming SSH if we can't determine
        true
      end

      # Check if the provider supports SSH
      def provider_supports_ssh?
        provider_name = @machine.provider_name
        return true unless provider_name
        
        # List of providers known to support SSH
        ssh_providers = [
          :virtualbox, :vmware_desktop, :vmware_fusion, :vmware_workstation,
          :libvirt, :kvm, :qemu, :parallels, :hyper_v, :lxc, :docker,
          :aws, :azure, :google, :digitalocean, :linode, :vultr
        ]
        
        # Providers known to NOT support SSH
        non_ssh_providers = [:winrm]
        
        return false if non_ssh_providers.include?(provider_name)
        
        # If it's a known SSH provider or unknown (assume SSH), return true
        ssh_providers.include?(provider_name) || !non_ssh_providers.include?(provider_name)
      rescue
        # Default to assuming SSH support if we can't determine
        true
      end

      # Validate that SSH info contains required fields
      def valid_ssh_info?(ssh_info)
        return false if ssh_info.nil?
        return false if ssh_info[:host].nil? || ssh_info[:host].to_s.strip.empty?
        return false if ssh_info[:port].nil? || ssh_info[:port].to_i <= 0
        
        # Username is not strictly required (can default to 'vagrant')
        # but if present, it shouldn't be empty
        if ssh_info[:username]
          return false if ssh_info[:username].to_s.strip.empty?
        end
        
        true
      rescue
        false
      end

      # Enhanced SSH info extraction with edge case handling
      def extract_ssh_info_safe
        return nil unless machine_supports_ssh?
        
        retries = 0
        max_retries = 3
        retry_delay = 1
        
        begin
          ssh_info = @machine.ssh_info
          return nil unless valid_ssh_info?(ssh_info)
          
          build_ssh_config(ssh_info)
        rescue Vagrant::Errors::SSHNotReady => e
          retries += 1
          if retries <= max_retries
            @logger.debug("SSH not ready, retrying in #{retry_delay}s (attempt #{retries}/#{max_retries})")
            sleep(retry_delay)
            retry_delay *= 2  # Exponential backoff
            retry
          else
            @logger.debug("SSH still not ready after #{max_retries} attempts")
            nil
          end
        rescue => e
          @logger.warn("SSH info extraction failed: #{e.message}")
          nil
        end
      end

      # Safe host name generation with fallbacks
      def generate_host_name
        begin
          # Generate a unique host name based on project directory and machine name
          project_name = File.basename(@machine.env.root_path)
          machine_name = @machine.name.to_s
          
          # Sanitize names for SSH config
          project_name = sanitize_name(project_name)
          machine_name = sanitize_name(machine_name)
          
          host_name = "#{project_name}-#{machine_name}"
          
          # Ensure the host name is not empty after sanitization
          if host_name.strip.empty? || host_name == '-'
            host_name = "vagrant-#{@machine.id || 'unknown'}"
          end
          
          host_name
        rescue => e
          @logger.debug("Host name generation failed: #{e.message}")
          "vagrant-#{@machine.name || 'unknown'}"
        end
      end

      # Normalize SSH config data to ensure consistency
      def normalize_ssh_config(config)
        normalized = {}
        
        config.each do |key, value|
          # Normalize key names to proper SSH config format
          normalized_key = normalize_config_key(key)
          normalized_value = normalize_config_value(key, value)
          
          normalized[normalized_key] = normalized_value if normalized_value
        end
        
        normalized
      end

      # Parse SSH config entries back from file format
      def parse_ssh_config_entry(entry_text)
        config = {}
        current_host = nil
        
        entry_text.split("\n").each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')
          
          if line.start_with?('Host ')
            current_host = line.sub(/^Host\s+/, '').strip
            config['Host'] = current_host
          elsif current_host && line.include?(' ')
            key, value = line.split(' ', 2)
            config[key.strip] = value.strip
          end
        end
        
        config
      end

      # Convert normalized config back to SSH config file format
      def to_ssh_config_format(config)
        lines = []
        
        # Host entry always comes first
        if config['Host']
          lines << "Host #{config['Host']}"
          
          # Add other entries in a logical order
          ssh_option_order = %w[
            HostName User Port IdentityFile IdentitiesOnly
            StrictHostKeyChecking UserKnownHostsFile PasswordAuthentication
            LogLevel ProxyCommand Compression CompressionLevel
            ConnectTimeout ForwardAgent ForwardX11
          ]
          
          ssh_option_order.each do |key|
            if config[key]
              lines << "  #{key} #{config[key]}"
            end
          end
          
          # Add any remaining options not in the predefined order
          config.each do |key, value|
            next if key == 'Host' || ssh_option_order.include?(key)
            lines << "  #{key} #{value}"
          end
        end
        
        lines.join("\n")
      end

      private

      def build_ssh_config(ssh_info)
        config = {
          'Host' => generate_host_name,
          'HostName' => ssh_info[:host],
          'User' => ssh_info[:username] || 'vagrant',
          'Port' => ssh_info[:port] || 22
        }

        # Add SSH key information
        if ssh_info[:private_key_path] && !ssh_info[:private_key_path].empty?
          # Use the first private key if multiple are provided
          key_path = ssh_info[:private_key_path].is_a?(Array) ? 
                     ssh_info[:private_key_path].first : 
                     ssh_info[:private_key_path]
          config['IdentityFile'] = key_path
          config['IdentitiesOnly'] = 'yes'
        end

        # Add common SSH options for Vagrant VMs
        config['StrictHostKeyChecking'] = 'no'
        config['UserKnownHostsFile'] = '/dev/null'
        config['PasswordAuthentication'] = 'no'
        config['LogLevel'] = 'FATAL'

        # Add proxy command if using a proxy
        if ssh_info[:proxy_command]
          config['ProxyCommand'] = ssh_info[:proxy_command]
        end

        # Add comprehensive SSH options from the machine config
        add_comprehensive_ssh_options(config, ssh_info)

        # Normalize the final configuration
        normalize_ssh_config(config)
      end

      # Add comprehensive SSH options support
      def add_comprehensive_ssh_options(config, ssh_info)
        return unless ssh_info[:config] && ssh_info[:config].ssh
        
        ssh_config = ssh_info[:config].ssh
        
        # Connection options
        config['Compression'] = ssh_config.compression ? 'yes' : 'no' if ssh_config.compression != nil
        config['CompressionLevel'] = ssh_config.compression_level.to_s if ssh_config.compression_level
        config['ConnectTimeout'] = ssh_config.connect_timeout.to_s if ssh_config.connect_timeout
        config['ConnectionAttempts'] = ssh_config.connection_attempts.to_s if ssh_config.connection_attempts
        config['ServerAliveInterval'] = ssh_config.server_alive_interval.to_s if ssh_config.server_alive_interval
        config['ServerAliveCountMax'] = ssh_config.server_alive_count_max.to_s if ssh_config.server_alive_count_max
        
        # Authentication options
        config['ForwardAgent'] = ssh_config.forward_agent ? 'yes' : 'no' if ssh_config.forward_agent != nil
        config['PubkeyAuthentication'] = ssh_config.pubkey_authentication ? 'yes' : 'no' if ssh_config.pubkey_authentication != nil
        config['PreferredAuthentications'] = ssh_config.preferred_authentications if ssh_config.preferred_authentications
        
        # Forwarding options
        config['ForwardX11'] = ssh_config.forward_x11 ? 'yes' : 'no' if ssh_config.forward_x11 != nil
        config['ForwardX11Trusted'] = ssh_config.forward_x11_trusted ? 'yes' : 'no' if ssh_config.forward_x11_trusted != nil
        
        # Security options
        config['StrictHostKeyChecking'] = ssh_config.verify_host_key ? 'yes' : 'no' if ssh_config.verify_host_key != nil
        config['CheckHostIP'] = ssh_config.check_host_ip ? 'yes' : 'no' if ssh_config.check_host_ip != nil
        
        # Protocol options
        config['Protocol'] = ssh_config.protocol if ssh_config.protocol
        config['Ciphers'] = ssh_config.ciphers.join(',') if ssh_config.ciphers && !ssh_config.ciphers.empty?
        config['MACs'] = ssh_config.macs.join(',') if ssh_config.macs && !ssh_config.macs.empty?
        config['KexAlgorithms'] = ssh_config.kex_algorithms.join(',') if ssh_config.kex_algorithms && !ssh_config.kex_algorithms.empty?
        
        # Terminal options
        config['RequestTTY'] = ssh_config.pty ? 'yes' : 'no' if ssh_config.pty != nil
        config['RemoteCommand'] = ssh_config.remote_command if ssh_config.remote_command
        
        # File and directory options
        config['ControlMaster'] = ssh_config.control_master if ssh_config.control_master
        config['ControlPath'] = ssh_config.control_path if ssh_config.control_path
        config['ControlPersist'] = ssh_config.control_persist.to_s if ssh_config.control_persist
        
        # Logging options
        config['LogLevel'] = ssh_config.log_level.to_s.upcase if ssh_config.log_level
        config['SyslogFacility'] = ssh_config.syslog_facility if ssh_config.syslog_facility
        
        # Banner and environment
        config['Banner'] = ssh_config.banner if ssh_config.banner
        config['SendEnv'] = ssh_config.send_env.join(' ') if ssh_config.send_env && !ssh_config.send_env.empty?
        config['SetEnv'] = ssh_config.set_env.map { |k, v| "#{k}=#{v}" }.join(' ') if ssh_config.set_env && !ssh_config.set_env.empty?
        
        # Keep alive options
        config['TCPKeepAlive'] = ssh_config.tcp_keep_alive ? 'yes' : 'no' if ssh_config.tcp_keep_alive != nil
        
        # Escape character
        config['EscapeChar'] = ssh_config.escape_char if ssh_config.escape_char
        
        # Gateway options
        config['ProxyJump'] = ssh_config.proxy_jump if ssh_config.proxy_jump
        
        # Add any custom options that might be defined
        if ssh_config.respond_to?(:extra_options) && ssh_config.extra_options
          ssh_config.extra_options.each do |key, value|
            config[key.to_s] = value.to_s
          end
        end
      end

      def generate_host_name
        # Generate a unique host name based on project directory and machine name
        project_name = File.basename(@machine.env.root_path)
        machine_name = @machine.name.to_s
        
        # Sanitize names for SSH config
        project_name = sanitize_name(project_name)
        machine_name = sanitize_name(machine_name)
        
        "#{project_name}-#{machine_name}"
      end

      def sanitize_name(name)
        # Remove or replace characters that might cause issues in SSH config
        name.gsub(/[^a-zA-Z0-9\-_]/, '-').gsub(/-+/, '-').gsub(/^-|-$/, '')
      end

      def normalize_config_key(key)
        # Convert various key formats to standard SSH config format
        key_mappings = {
          'hostname' => 'HostName',
          'host_name' => 'HostName',
          'user' => 'User',
          'username' => 'User',
          'port' => 'Port',
          'identity_file' => 'IdentityFile',
          'identityfile' => 'IdentityFile',
          'identities_only' => 'IdentitiesOnly',
          'identitiesonly' => 'IdentitiesOnly',
          'strict_host_key_checking' => 'StrictHostKeyChecking',
          'stricthostkeychecking' => 'StrictHostKeyChecking',
          'user_known_hosts_file' => 'UserKnownHostsFile',
          'userknownhostsfile' => 'UserKnownHostsFile',
          'password_authentication' => 'PasswordAuthentication',
          'passwordauthentication' => 'PasswordAuthentication',
          'log_level' => 'LogLevel',
          'loglevel' => 'LogLevel',
          'proxy_command' => 'ProxyCommand',
          'proxycommand' => 'ProxyCommand',
          'compression' => 'Compression',
          'compression_level' => 'CompressionLevel',
          'compressionlevel' => 'CompressionLevel',
          'connect_timeout' => 'ConnectTimeout',
          'connecttimeout' => 'ConnectTimeout',
          'forward_agent' => 'ForwardAgent',
          'forwardagent' => 'ForwardAgent',
          'forward_x11' => 'ForwardX11',
          'forwardx11' => 'ForwardX11'
        }
        
        key_str = key.to_s.downcase
        key_mappings[key_str] || key.to_s
      end

      def normalize_config_value(key, value)
        return nil if value.nil? || value.to_s.strip.empty?
        
        case key.to_s.downcase
        when 'port'
          value.to_i.to_s
        when 'compression', 'identitiesonly', 'stricthostkeychecking', 
             'passwordauthentication', 'forwardagent', 'forwardx11'
          # Normalize boolean-like values
          case value.to_s.downcase
          when 'true', 'yes', '1'
            'yes'
          when 'false', 'no', '0'
            'no'
          else
            value.to_s
          end
        when 'identityfile'
          # Expand tilde in file paths
          File.expand_path(value.to_s)
        else
          value.to_s.strip
        end
      end
    end
  end
end
