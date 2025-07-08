require 'fileutils'
require 'digest'
require 'tempfile'
require 'log4r'

module VagrantPlugins
  module SshConfigManager
    class FileManager
      # Initialize FileManager with configuration
      def initialize(config)
        @config = config
        @logger = Log4r::Logger.new("vagrant::plugins::sshconfigmanager::filemanager")
      end

      # Generate unique filename for VM SSH config
      # Format: {project_hash}-{vm_name}.conf
      def generate_filename(machine)
        project_hash = generate_project_hash(machine.env.root_path.to_s)
        vm_name = machine.name.to_s
        "#{project_hash}-#{vm_name}.conf"
      end

      # Get full path for VM SSH config file
      def get_file_path(machine)
        filename = generate_filename(machine)
        File.join(@config.ssh_config_dir, filename)
      end

      # Generate SSH config content for a VM
      def generate_ssh_config_content(machine)
        ssh_info = machine.ssh_info
        return nil unless ssh_info

        content = []
        content << "# Managed by vagrant-ssh-config-manager plugin"
        content << "# Project: #{File.basename(machine.env.root_path)}"
        content << "# VM: #{machine.name}"
        content << "# Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
        content << ""
        
        host_name = generate_host_name(machine)
        content << "Host #{host_name}"
        content << "  HostName #{ssh_info[:host]}"
        content << "  Port #{ssh_info[:port]}"
        content << "  User #{ssh_info[:username]}"
        
        if ssh_info[:private_key_path] && ssh_info[:private_key_path].first
          content << "  IdentityFile #{ssh_info[:private_key_path].first}"
          content << "  IdentitiesOnly yes"
        end
        
        content << "  UserKnownHostsFile /dev/null"
        content << "  StrictHostKeyChecking no"
        content << "  PasswordAuthentication no"
        content << "  LogLevel FATAL"
        content << ""

        content.join("\n")
      end

      # Write SSH config file for VM with atomic operation
      def write_ssh_config_file(machine)
        return false unless @config.enabled

        file_path = get_file_path(machine)
        content = generate_ssh_config_content(machine)
        return false unless content

        begin
          # Ensure directory exists
          FileUtils.mkdir_p(File.dirname(file_path), mode: 0700)
          
          # Use atomic write with temporary file
          write_file_atomically(file_path, content)
          
          @logger.info("SSH config file created: #{file_path}")
          true
        rescue => e
          @logger.error("Failed to write SSH config file #{file_path}: #{e.message}")
          false
        end
      end

      # Remove SSH config file for VM
      def remove_ssh_config_file(machine)
        file_path = get_file_path(machine)
        
        begin
          if File.exist?(file_path)
            File.delete(file_path)
            @logger.info("SSH config file removed: #{file_path}")
            
            # Clean up empty directory if configured
            cleanup_empty_directory if @config.cleanup_empty_dir
            true
          else
            @logger.debug("SSH config file does not exist: #{file_path}")
            false
          end
        rescue => e
          @logger.error("Failed to remove SSH config file #{file_path}: #{e.message}")
          false
        end
      end

      # Check if SSH config file exists for VM
      def ssh_config_file_exists?(machine)
        File.exist?(get_file_path(machine))
      end

      # Validate SSH config file content
      def validate_ssh_config_content(content)
        return false if content.nil? || content.empty?
        
        # Basic validation - check for required SSH config elements
        content.include?("Host ") && content.include?("HostName ") && content.include?("Port ")
      end

      # Detect and clean up orphaned SSH config files
      def cleanup_orphaned_files
        return unless Dir.exist?(@config.ssh_config_dir)

        orphaned_files = []
        config_files = Dir.glob(File.join(@config.ssh_config_dir, "*.conf"))

        config_files.each do |file_path|
          filename = File.basename(file_path, ".conf")
          
          # Parse filename to extract project hash and VM name
          if filename.match(/^([a-f0-9]{8})-(.+)$/)
            project_hash = $1
            vm_name = $2
            
            # Check if this looks like an orphaned file
            # (This is a basic heuristic - in practice, you might want more sophisticated detection)
            file_age = Time.now - File.mtime(file_path)
            
            # Consider files older than 30 days as potentially orphaned
            if file_age > (30 * 24 * 60 * 60) # 30 days in seconds
              orphaned_files << {
                path: file_path,
                project_hash: project_hash,
                vm_name: vm_name,
                age_days: (file_age / (24 * 60 * 60)).round
              }
            end
          end
        end

        # Log detected orphaned files
        unless orphaned_files.empty?
          @logger.info("Detected #{orphaned_files.length} potentially orphaned SSH config files")
          orphaned_files.each do |file_info|
            @logger.debug("Orphaned file: #{file_info[:path]} (#{file_info[:age_days]} days old)")
          end
        end

        orphaned_files
      end

      # Remove orphaned SSH config files
      def remove_orphaned_files
        orphaned_files = cleanup_orphaned_files
        removed_count = 0

        orphaned_files.each do |file_info|
          begin
            File.delete(file_info[:path])
            @logger.info("Removed orphaned SSH config file: #{file_info[:path]}")
            removed_count += 1
          rescue => e
            @logger.error("Failed to remove orphaned file #{file_info[:path]}: #{e.message}")
          end
        end

        # Clean up empty directory if configured
        cleanup_empty_directory if @config.cleanup_empty_dir && removed_count > 0

        removed_count
      end

      # Get all config files in the directory
      def get_all_config_files
        return [] unless Dir.exist?(@config.ssh_config_dir)
        Dir.glob(File.join(@config.ssh_config_dir, "*.conf"))
      end

      private

      # Generate unique project hash from root path
      def generate_project_hash(root_path)
        Digest::MD5.hexdigest(root_path)[0, 8]
      end

      # Generate SSH host name for machine
      def generate_host_name(machine)
        if @config.project_isolation
          project_name = File.basename(machine.env.root_path)
          "#{project_name}-#{machine.name}"
        else
          machine.name.to_s
        end
      end

      # Write file atomically using temporary file and rename
      def write_file_atomically(file_path, content)
        temp_file = Tempfile.new(File.basename(file_path), File.dirname(file_path))
        begin
          temp_file.write(content)
          temp_file.close
          
          # Set proper permissions before moving
          File.chmod(0600, temp_file.path)
          
          # Atomic move
          FileUtils.mv(temp_file.path, file_path)
        ensure
          temp_file.unlink if temp_file && File.exist?(temp_file.path)
        end
      end

      # Clean up empty directory if no config files remain
      def cleanup_empty_directory
        return unless Dir.exist?(@config.ssh_config_dir)
        
        entries = Dir.entries(@config.ssh_config_dir) - %w[. ..]
        if entries.empty?
          begin
            # Remove Include directive before removing directory
            if @config.manage_includes
              require_relative 'include_manager'
              include_manager = IncludeManager.new(@config)
              include_manager.remove_include_directive
            end
            
            Dir.rmdir(@config.ssh_config_dir)
            @logger.info("Removed empty SSH config directory: #{@config.ssh_config_dir}")
          rescue => e
            @logger.error("Failed to remove empty directory #{@config.ssh_config_dir}: #{e.message}")
          end
        end
      end
    end
  end
end
