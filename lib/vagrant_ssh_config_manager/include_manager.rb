# frozen_string_literal: true

require 'fileutils'
require 'tempfile'
require 'log4r'

module VagrantPlugins
  module SshConfigManager
    class IncludeManager
      PLUGIN_MARKER_START = '# BEGIN vagrant-ssh-config-manager'
      PLUGIN_MARKER_END = '# END vagrant-ssh-config-manager'

      # Initialize IncludeManager with configuration
      def initialize(config)
        @config = config
        @logger = Log4r::Logger.new('vagrant::plugins::sshconfigmanager::includemanager')
      end

      # Get the SSH config file path (always ~/.ssh/config)
      def ssh_config_file
        @ssh_config_file ||= File.expand_path('~/.ssh/config')
      end

      # Check if Include directive exists in main SSH config
      def include_directive_exists?
        return false unless File.exist?(ssh_config_file)

        content = File.read(ssh_config_file)
        include_pattern = /^Include\s+#{Regexp.escape(@config.ssh_config_dir)}/
        content.match?(include_pattern)
      end

      # Add Include directive to main SSH config file
      def add_include_directive
        return false unless @config.manage_includes
        return true if include_directive_exists?

        begin
          # Create backup before modifying
          create_backup

          # Add Include directive at the beginning of file
          add_include_to_config

          @logger.info("Added Include directive for #{@config.ssh_config_dir} to ~/.ssh/config")
          true
        rescue StandardError => e
          @logger.error("Failed to add Include directive: #{e.message}")
          restore_backup
          false
        end
      end

      # Remove Include directive from main SSH config file
      def remove_include_directive
        return false unless @config.manage_includes
        return true unless include_directive_exists?

        begin
          # Create backup before modifying
          create_backup

          # Remove Include directive
          remove_include_from_config

          @logger.info("Removed Include directive for #{@config.ssh_config_dir} from ~/.ssh/config")
          true
        rescue StandardError => e
          @logger.error("Failed to remove Include directive: #{e.message}")
          restore_backup
          false
        end
      end

      # Check if Include directive should be removed (no config files exist)
      def should_remove_include_directive?
        return false unless @config.cleanup_empty_dir
        return false unless Dir.exist?(@config.ssh_config_dir)

        # Check if directory is empty (excluding . and ..)
        entries = Dir.entries(@config.ssh_config_dir) - %w[. ..]
        config_files = entries.select { |file| file.end_with?('.conf') }
        config_files.empty?
      end

      # Manage Include directive based on current state
      def manage_include_directive
        return unless @config.manage_includes

        if should_remove_include_directive?
          remove_include_directive
        elsif Dir.exist?(@config.ssh_config_dir) && Dir.entries(@config.ssh_config_dir).any? do |f|
          File.file?(File.join(@config.ssh_config_dir, f)) && f.end_with?('.conf')
        end
          add_include_directive
        end
      end

      # Parse SSH config file and find optimal location for Include
      def find_include_location(content)
        lines = content.lines

        # Look for existing Include directives to place ours with them
        include_line_index = lines.find_index { |line| line.strip.start_with?('Include ') }

        if include_line_index
          # Place before other Include directives
          include_line_index
        else
          # Place at the beginning of file, after any initial comments
          comment_end = 0
          lines.each_with_index do |line, index|
            break unless line.strip.empty? || line.strip.start_with?('#')

            comment_end = index + 1
          end
          comment_end
        end
      end

      # Check if main SSH config file is write-protected
      def main_config_writable?
        return false unless File.exist?(ssh_config_file)

        File.writable?(ssh_config_file)
      end

      # Handle edge case: empty main config file
      def handle_empty_main_config
        return if File.exist?(ssh_config_file)

        # Create empty SSH config file with proper permissions
        FileUtils.mkdir_p(File.dirname(ssh_config_file), mode: 0o700)
        File.write(ssh_config_file, '')
        File.chmod(0o600, ssh_config_file)
        @logger.info("Created empty SSH config file: #{ssh_config_file}")
      end

      # Validate SSH config file format
      def validate_main_config
        return true unless File.exist?(ssh_config_file)

        begin
          content = File.read(ssh_config_file)
          # Basic validation - check for severely malformed config
          lines = content.lines
          lines.each_with_index do |line, index|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?('#')

            # Check for basic SSH config format issues
            if stripped.include?("\t") && stripped.start_with?('Host ')
              @logger.warn("Potential SSH config format issue at line #{index + 1}: tabs in Host directive")
            end
          end
          true
        rescue StandardError => e
          @logger.error("SSH config validation failed: #{e.message}")
          false
        end
      end

      private

      # Create backup of main SSH config file
      def create_backup
        backup_path = "#{ssh_config_file}.vagrant-ssh-config-manager.backup"
        FileUtils.cp(ssh_config_file, backup_path) if File.exist?(ssh_config_file)
        @backup_path = backup_path
      end

      # Restore backup of main SSH config file
      def restore_backup
        return unless @backup_path && File.exist?(@backup_path)

        FileUtils.cp(@backup_path, ssh_config_file)
        File.delete(@backup_path)
        @logger.info('Restored SSH config from backup')
      end

      # Add Include directive to SSH config
      def add_include_to_config
        handle_empty_main_config

        content = File.exist?(ssh_config_file) ? File.read(ssh_config_file) : ''
        lines = content.lines

        # Find optimal location for Include
        insert_index = find_include_location(content)

        # Create Include directive with plugin markers
        include_lines = [
          "#{PLUGIN_MARKER_START}\n",
          "Include #{@config.ssh_config_dir}/*.conf\n",
          "#{PLUGIN_MARKER_END}\n",
          "\n"
        ]

        # Insert Include directive
        lines.insert(insert_index, *include_lines)

        # Write back to file atomically
        write_config_atomically(lines.join)
      end

      # Remove Include directive from SSH config
      def remove_include_from_config
        return unless File.exist?(ssh_config_file)

        content = File.read(ssh_config_file)
        lines = content.lines

        # Find and remove plugin-managed Include directive
        start_index = lines.find_index { |line| line.strip == PLUGIN_MARKER_START.strip }
        end_index = lines.find_index { |line| line.strip == PLUGIN_MARKER_END.strip }

        if start_index && end_index && end_index > start_index
          # Remove lines between markers (inclusive)
          lines.slice!(start_index..end_index)

          # Remove trailing empty line if it exists
          lines.delete_at(start_index) if lines[start_index] && lines[start_index].strip.empty?
        else
          # Fallback: remove any Include directive for our directory
          lines.reject! do |line|
            line.strip.match?(/^Include\s+#{Regexp.escape(@config.ssh_config_dir)}/)
          end
        end

        # Write back to file atomically
        write_config_atomically(lines.join)
      end

      # Write SSH config file atomically
      def write_config_atomically(content)
        temp_file = Tempfile.new(File.basename(ssh_config_file), File.dirname(ssh_config_file))
        begin
          temp_file.write(content)
          temp_file.close

          # Set proper permissions before moving
          File.chmod(0o600, temp_file.path)

          # Atomic move
          FileUtils.mv(temp_file.path, ssh_config_file)
        ensure
          temp_file.unlink if temp_file && File.exist?(temp_file.path)
        end
      end
    end
  end
end
