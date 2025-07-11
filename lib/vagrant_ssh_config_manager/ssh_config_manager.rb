# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'digest'
require_relative 'file_locker'

module VagrantPlugins
  module SshConfigManager
    class SshConfigManager
      attr_reader :ssh_config_file, :project_name

      def initialize(machine, config = nil)
        @machine = machine
        @config = config || machine.config.sshconfigmanager
        @logger = Log4r::Logger.new('vagrant::plugins::ssh_config_manager::ssh_config_manager')

        # Determine SSH config file path
        @ssh_config_file = determine_ssh_config_file
        @project_name = generate_project_name
        @include_file_path = generate_include_file_path
      end

      # Add SSH configuration entry for a machine
      def add_ssh_entry(ssh_config_data)
        return false unless ssh_config_data && ssh_config_data['Host']

        begin
          ensure_ssh_config_structure
          write_include_file(ssh_config_data)
          add_include_directive

          @logger.info("Added SSH entry for host: #{ssh_config_data['Host']}")
          true
        rescue StandardError => e
          @logger.error("Failed to add SSH entry: #{e.message}")
          false
        end
      end

      # Remove SSH configuration entry for a machine
      def remove_ssh_entry(host_name)
        return false unless host_name

        begin
          removed = remove_from_include_file(host_name)
          cleanup_empty_include_file
          cleanup_include_directive_if_needed

          @logger.info("Removed SSH entry for host: #{host_name}") if removed
          removed
        rescue StandardError => e
          @logger.error("Failed to remove SSH entry: #{e.message}")
          false
        end
      end

      # Update SSH configuration entry for a machine
      def update_ssh_entry(ssh_config_data)
        return false unless ssh_config_data && ssh_config_data['Host']

        begin
          host_name = ssh_config_data['Host']
          remove_ssh_entry(host_name)
          add_ssh_entry(ssh_config_data)

          @logger.info("Updated SSH entry for host: #{host_name}")
          true
        rescue StandardError => e
          @logger.error("Failed to update SSH entry: #{e.message}")
          false
        end
      end

      # Check if SSH entry exists for a host
      def ssh_entry_exists?(host_name)
        return false unless File.exist?(@include_file_path)

        content = File.read(@include_file_path)
        content.include?("Host #{host_name}")
      rescue StandardError
        false
      end

      # List all SSH entries managed by this project
      def project_ssh_entries
        return [] unless File.exist?(@include_file_path)

        entries = []
        current_entry = nil

        File.readlines(@include_file_path).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')

          if line.start_with?('Host ')
            entries << current_entry if current_entry
            current_entry = { 'Host' => line.sub(/^Host\s+/, '') }
          elsif current_entry && line.include?(' ')
            key, value = line.split(' ', 2)
            current_entry[key.strip] = value.strip
          end
        end

        entries << current_entry if current_entry
        entries
      rescue StandardError
        []
      end

      # alias old name for backward compatibility if needed
      alias get_project_ssh_entries project_ssh_entries

      # Get include file status and information
      def include_file_info
        info = {
          path: @include_file_path,
          exists: File.exist?(@include_file_path),
          size: 0,
          entries_count: 0,
          last_modified: nil
        }

        if info[:exists]
          stat = File.stat(@include_file_path)
          info[:size] = stat.size
          info[:last_modified] = stat.mtime
          info[:entries_count] = count_entries_in_include_file
        end

        info
      end

      # Backup include file before operations
      def backup_include_file
        return nil unless File.exist?(@include_file_path)

        backup_path = "#{@include_file_path}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        FileUtils.cp(@include_file_path, backup_path)

        @logger.debug("Created backup of include file: #{backup_path}")
        backup_path
      rescue StandardError => e
        @logger.warn("Failed to create backup: #{e.message}")
        nil
      end

      # Restore include file from backup
      def restore_include_file(backup_path)
        return false unless File.exist?(backup_path)

        begin
          FileUtils.cp(backup_path, @include_file_path)
          @logger.info("Restored include file from backup: #{backup_path}")
          true
        rescue StandardError => e
          @logger.error("Failed to restore from backup: #{e.message}")
          false
        end
      end

      # Validate include file format and structure
      def validate_include_file
        return { valid: true, errors: [] } unless File.exist?(@include_file_path)

        errors = []
        line_number = 0
        current_host = nil

        begin
          File.readlines(@include_file_path).each do |line|
            line_number += 1
            line_stripped = line.strip

            next if line_stripped.empty? || line_stripped.start_with?('#')

            if line_stripped.start_with?('Host ')
              host_name = line_stripped.sub(/^Host\s+/, '')
              if host_name.empty?
                errors << "Line #{line_number}: Empty host name"
              else
                current_host = host_name
              end
            elsif current_host
              errors << "Line #{line_number}: Invalid SSH option format" unless line_stripped.include?(' ')
            else
              errors << "Line #{line_number}: SSH option without host declaration"
            end
          end
        rescue StandardError => e
          errors << "Failed to read include file: #{e.message}"
        end

        {
          valid: errors.empty?,
          errors: errors,
          path: @include_file_path
        }
      end

      # Clean up orphaned include files (for debugging/maintenance)
      def cleanup_orphaned_include_files
        config_d_dir = File.dirname(@include_file_path)
        return 0 unless File.exist?(config_d_dir)

        cleaned_count = 0

        Dir.glob(File.join(config_d_dir, 'vagrant-*')).each do |file_path|
          next unless File.file?(file_path)

          # Check if file is empty or only contains comments
          content = File.read(file_path).strip
          next unless content.empty? || content.lines.all? { |line| line.strip.empty? || line.strip.start_with?('#') }

          File.delete(file_path)
          cleaned_count += 1
          @logger.debug("Cleaned up orphaned include file: #{file_path}")
        end

        cleaned_count
      rescue StandardError => e
        @logger.warn("Failed to cleanup orphaned files: #{e.message}")
        0
      end

      # Advanced main SSH config file management

      # Get information about main SSH config file
      def main_config_info
        info = {
          path: @ssh_config_file,
          exists: File.exist?(@ssh_config_file),
          size: 0,
          writable: false,
          include_directive_exists: false,
          last_modified: nil
        }

        if info[:exists]
          stat = File.stat(@ssh_config_file)
          info[:size] = stat.size
          info[:last_modified] = stat.mtime
          info[:writable] = File.writable?(@ssh_config_file)
          info[:include_directive_exists] = include_directive_exists?
        end

        info
      end

      # Safely add include directive with conflict detection
      def add_include_directive_safe
        return true if include_directive_exists?

        begin
          # Check if main config file is writable
          unless File.writable?(@ssh_config_file) || !File.exist?(@ssh_config_file)
            @logger.warn("SSH config file is not writable: #{@ssh_config_file}")
            return false
          end

          backup_main_config
          add_include_directive_with_validation
          true
        rescue StandardError => e
          @logger.error("Failed to add include directive safely: #{e.message}")
          false
        end
      end

      # Remove include directive and clean up
      def remove_include_directive_safe
        return true unless include_directive_exists?

        begin
          backup_main_config
          remove_include_directive_with_validation
          true
        rescue StandardError => e
          @logger.error("Failed to remove include directive safely: #{e.message}")
          false
        end
      end

      # Validate main SSH config file structure
      def validate_main_config
        return { valid: true, errors: [], warnings: [] } unless File.exist?(@ssh_config_file)

        errors = []
        warnings = []
        line_number = 0

        begin
          File.readlines(@ssh_config_file).each do |line|
            line_number += 1
            line_stripped = line.strip

            next if line_stripped.empty? || line_stripped.start_with?('#')

            # Check for include directive syntax
            if line_stripped.start_with?('Include ')
              include_path = line_stripped.sub(/^Include\s+/, '')
              unless File.exist?(File.expand_path(include_path))
                warnings << "Line #{line_number}: Include file does not exist: #{include_path}"
              end
            end

            # Check for potential conflicts with our include
            if line_stripped.start_with?('Host ') && line_stripped.include?(@project_name)
              warnings << "Line #{line_number}: Potential host name conflict detected"
            end
          end
        rescue StandardError => e
          errors << "Failed to read main config file: #{e.message}"
        end

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings,
          path: @ssh_config_file
        }
      end

      # Fetch Include directives from the SSH include file
      def include_directives
        return [] unless File.exist?(@include_file_path)

        directives = []
        line_number = 0

        File.readlines(@include_file_path).each do |line|
          line_number += 1
          line_stripped = line.strip

          next unless line_stripped.start_with?('Include ')

          include_path = line_stripped.sub(/^Include\s+/, '')
          directives << {
            line_number: line_number,
            path: include_path,
            absolute_path: File.expand_path(include_path),
            exists: File.exist?(File.expand_path(include_path)),
            is_ours: include_path == @include_file_path
          }
        end

        directives
      rescue StandardError => e
        @logger.warn("Failed to get include directives: #{e.message}")
        []
      end
      alias get_include_directives include_directives

      # Check for conflicts with existing SSH config
      def check_host_conflicts(host_name)
        conflicts = []
        return conflicts unless File.exist?(@ssh_config_file)

        # Check in main config file
        conflicts.concat(find_host_in_file(@ssh_config_file, host_name, 'main config'))

        # Check in other include files
        include_directives.each do |include_info|
          next if include_info[:is_ours] || !include_info[:exists]

          conflicts.concat(find_host_in_file(
                             include_info[:absolute_path],
                             host_name,
                             "include file: #{include_info[:path]}"
                           ))
        end

        conflicts
      end

      # Project-based naming and isolation methods

      # Generate unique project identifier
      def generate_project_identifier
        # Use multiple factors to ensure uniqueness
        project_path = @machine.env.root_path
        project_name = File.basename(project_path)

        # Create a hash of the full path for uniqueness
        path_hash = Digest::SHA256.hexdigest(project_path.to_s)[0..7]

        # Combine sanitized name with hash
        base_name = sanitize_name(project_name)
        "#{base_name}-#{path_hash}"
      end

      # Generate host name with project isolation
      def generate_isolated_host_name(machine_name)
        project_id = generate_project_identifier
        machine_name_clean = sanitize_name(machine_name.to_s)

        # Format: project-hash-machine
        host_name = "#{project_id}-#{machine_name_clean}"

        # Ensure host name is not too long (SSH has practical limits)
        truncate_host_name(host_name)
      end

      # List project host names
      def project_hosts
        hosts = []
        project_id = generate_project_identifier

        # Search in our include file
        hosts.concat(extract_hosts_from_file(@include_file_path, project_id)) if File.exist?(@include_file_path)

        hosts
      end
      alias get_project_hosts project_hosts

      # Check if a host belongs to this project
      def project_owns_host?(host_name)
        project_id = generate_project_identifier
        host_name.start_with?(project_id)
      end

      # Clean up all hosts for this project
      def cleanup_project_hosts
        cleaned_count = 0

        get_project_hosts.each do |host_name|
          cleaned_count += 1 if remove_ssh_entry(host_name)
        end

        @logger.info("Cleaned up #{cleaned_count} hosts for project: #{@project_name}")
        cleaned_count
      end

      # Get project statistics
      # Gather statistics about the project SSH entries
      def project_stats
        {
          project_name: @project_name,
          project_id: generate_project_identifier,
          project_path: @machine.env.root_path.to_s,
          include_file: @include_file_path,
          hosts_count: project_hosts.count,
          include_file_exists: File.exist?(@include_file_path),
          include_file_size: File.exist?(@include_file_path) ? File.size(@include_file_path) : 0
        }
      end
      alias get_project_stats project_stats

      # Migrate old naming scheme to new project-based scheme
      def migrate_to_project_naming?(old_host_names)
        return false if old_host_names.nil? || old_host_names.empty?

        migrated_count = 0

        old_host_names.each do |old_host_name|
          # Extract machine name from old host name
          machine_name = extract_machine_name_from_host(old_host_name)
          next unless machine_name

          # Generate new host name
          new_host_name = generate_isolated_host_name(machine_name)

          # Skip if names are the same
          next if old_host_name == new_host_name

          # Get SSH config for the old host
          ssh_config = find_ssh_config_for_host(old_host_name)
          next unless ssh_config

          # Update host name in config
          ssh_config['Host'] = new_host_name

          # Remove old entry and add new one
          if remove_ssh_entry(old_host_name) && add_ssh_entry(ssh_config)
            migrated_count += 1
            @logger.info("Migrated host: #{old_host_name} -> #{new_host_name}")
          end
        end

        @logger.info("Migrated #{migrated_count} hosts to project-based naming")
        migrated_count.positive?
      end
      alias migrate_to_project_naming migrate_to_project_naming?

      # List all Vagrant projects detected in SSH config
      def list_vagrant_projects
        projects = {}
        config_d_dir = File.dirname(@include_file_path)

        return projects unless File.exist?(config_d_dir)

        Dir.glob(File.join(config_d_dir, 'vagrant-*')).each do |file_path|
          next unless File.file?(file_path)

          # Extract project info from filename
          filename = File.basename(file_path)
          next unless filename.match(/^vagrant-(.+)$/)

          project_info = parse_project_from_filename(::Regexp.last_match(1))
          next unless project_info

          hosts = extract_hosts_from_file(file_path)

          projects[project_info[:id]] = {
            name: project_info[:name],
            id: project_info[:id],
            include_file: file_path,
            hosts: hosts,
            hosts_count: hosts.count,
            last_modified: File.mtime(file_path)
          }
        end

        projects
      end

      # Private API for helper methods

      private

      def truncate_host_name(host_name, max_length = 64)
        return host_name if host_name.length <= max_length

        # Keep the project hash part and truncate the machine name part
        parts = host_name.split('-')
        if parts.length >= 3
          # Keep project name and hash, truncate machine name
          project_part = parts[0..-2].join('-')
          machine_part = parts[-1]

          available_length = max_length - project_part.length - 1
          if available_length.positive?
            truncated_machine = machine_part[0...available_length]
            return "#{project_part}-#{truncated_machine}"
          end
        end

        # Fallback: simple truncation
        host_name[0...max_length]
      end

      def extract_hosts_from_file(file_path, project_filter = nil)
        hosts = []
        return hosts unless File.exist?(file_path)

        File.readlines(file_path).each do |line|
          line_stripped = line.strip
          next unless line_stripped.start_with?('Host ')

          host_name = line_stripped.sub(/^Host\s+/, '')
          # Apply project filter if specified
          hosts << host_name if project_filter.nil? || host_name.start_with?(project_filter)
        end

        hosts
      rescue StandardError => e
        @logger.warn("Failed to extract hosts from #{file_path}: #{e.message}")
        []
      end

      def extract_machine_name_from_host(host_name)
        # Try to extract machine name from various naming patterns

        # New project-based pattern: project-hash-machine
        return ::Regexp.last_match(1) if host_name.match(/^.+-[a-f0-9]{8}-(.+)$/)

        # Old pattern: project-machine
        parts = host_name.split('-')
        return parts.last if parts.length >= 2

        # Single name
        host_name
      end

      def find_ssh_config_for_host(host_name)
        entries = get_project_ssh_entries
        entries.find { |entry| entry['Host'] == host_name }
      end

      def parse_project_from_filename(filename_part)
        # Parse project info from include filename
        # Format: project-name-hash or just project-name

        if filename_part.match(/^(.+)-([a-f0-9]{8})$/)
          {
            name: ::Regexp.last_match(1),
            id: filename_part,
            hash: ::Regexp.last_match(2)
          }
        else
          {
            name: filename_part,
            id: filename_part,
            hash: nil
          }
        end
      end

      # Enhanced sanitization for project-based naming
      def sanitize_name(name)
        return 'unknown' if name.nil? || name.to_s.strip.empty?

        # Remove or replace problematic characters
        sanitized = name.to_s
                        .gsub(/[^a-zA-Z0-9\-_.]/, '-')  # Replace invalid chars
                        .gsub(/\.+/, '.')               # Collapse multiple dots
                        .gsub(/-+/, '-')                # Collapse multiple dashes
                        .gsub(/^[-._]+|[-._]+$/, '')    # Remove leading/trailing special chars
                        .downcase

        # Ensure name is not empty after sanitization
        sanitized.empty? ? 'unknown' : sanitized
      end

      def determine_ssh_config_file
        # Use custom path if specified, otherwise default to ~/.ssh/config
        if @config&.ssh_conf_file
          File.expand_path(@config.ssh_conf_file)
        else
          File.expand_path('~/.ssh/config')
        end
      end

      def generate_project_name
        return @project_name if @project_name

        # Use the new project identifier method for consistency
        @project_name = generate_project_identifier
      end

      def generate_include_file_path
        # Create include file path: ~/.ssh/config.d/vagrant-{project-name}
        ssh_dir = File.dirname(@ssh_config_file)
        config_d_dir = File.join(ssh_dir, 'config.d')
        File.join(config_d_dir, "vagrant-#{@project_name}")
      end

      def ensure_ssh_config_structure
        # Create SSH directory if it doesn't exist
        ssh_dir = File.dirname(@ssh_config_file)
        FileUtils.mkdir_p(ssh_dir, mode: 0o700)

        # Create config.d directory if it doesn't exist
        config_d_dir = File.dirname(@include_file_path)
        FileUtils.mkdir_p(config_d_dir, mode: 0o700)

        # Create main SSH config file if it doesn't exist
        return if File.exist?(@ssh_config_file)

        File.write(@ssh_config_file, "# SSH Config File\n")
        File.chmod(0o600, @ssh_config_file)
      end

      def write_include_file(ssh_config_data)
        # Prepare the SSH configuration content
        content = format_ssh_config_entry(ssh_config_data)

        # Write the include file
        File.write(@include_file_path, content)
        File.chmod(0o600, @include_file_path)

        @logger.debug("Wrote SSH config to include file: #{@include_file_path}")
      end

      # Comment markers and section management

      # Comment templates for different types of markers
      COMMENT_TEMPLATES = {
        file_header: [
          '# Vagrant SSH Config - Project: %<project_name>s',
          '# Generated on: %<timestamp>s',
          '# DO NOT EDIT MANUALLY - Managed by vagrant-ssh-config-manager',
          '# Plugin Version: %<version>s',
          '# Project Path: %<project_path>s'
        ],
        section_start: [
          '# === START: Vagrant SSH Config Manager ===',
          '# Project: %<project_name>s | Machine: %<machine_name>s',
          '# Generated: %<timestamp>s'
        ],
        section_end: [
          '# === END: Vagrant SSH Config Manager ==='
        ],
        include_directive: [
          '# Vagrant SSH Config Manager - Auto-generated include',
          '# Include file: %<include_file>s',
          '# Project: %<project_name>s'
        ],
        warning: [
          '# WARNING: This section is automatically managed',
          '# Manual changes will be overwritten'
        ]
      }.freeze

      # Helper methods should be private
      private

      # Add comprehensive comment markers to SSH entry
      def add_comment_markers_to_entry(ssh_config_data, machine_name = nil)
        return ssh_config_data unless ssh_config_data

        machine_name ||= @machine.name.to_s
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')

        # Create commented entry with markers
        lines = []

        # Section start marker
        lines.concat(format_comment_block(:section_start, {
                                            project_name: @project_name,
                                            machine_name: machine_name,
                                            timestamp: timestamp
                                          }))

        lines << ''

        # SSH configuration
        if ssh_config_data['Host']
          lines << "Host #{ssh_config_data['Host']}"

          # Add SSH options with inline comments for important ones
          ssh_option_order = %w[
            HostName User Port IdentityFile IdentitiesOnly
            StrictHostKeyChecking UserKnownHostsFile PasswordAuthentication
            LogLevel ProxyCommand Compression CompressionLevel
            ConnectTimeout ForwardAgent ForwardX11
          ]

          ssh_option_order.each do |key|
            next unless ssh_config_data[key]

            value = ssh_config_data[key]
            comment = get_option_comment(key, value)
            line = "  #{key} #{value}"
            line += "  # #{comment}" if comment
            lines << line
          end

          # Add any remaining options
          ssh_config_data.each do |key, value|
            next if key == 'Host' || ssh_option_order.include?(key)

            lines << "  #{key} #{value}"
          end
        end

        lines << ''

        # Section end marker
        lines.concat(format_comment_block(:section_end))

        {
          'Host' => ssh_config_data['Host'],
          'formatted_content' => lines.join("\n"),
          'raw_config' => ssh_config_data
        }
      end

      # Generate file header with comprehensive metadata
      def generate_file_header_with_markers
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        version = begin
          VagrantPlugins::SshConfigManager::VERSION
        rescue StandardError
          'unknown'
        end

        format_comment_block(:file_header, {
                               project_name: @project_name,
                               timestamp: timestamp,
                               version: version,
                               project_path: @machine.env.root_path.to_s
                             })
      end

      # Add warning markers to dangerous operations
      def add_warning_markers
        format_comment_block(:warning)
      end

      # Generate include directive with markers
      def generate_include_directive_with_markers
        lines = []

        lines.concat(format_comment_block(:include_directive, {
                                            include_file: @include_file_path,
                                            project_name: @project_name
                                          }))

        lines << "Include #{@include_file_path}"
        lines << ''

        lines
      end

      # Extract plugin-managed sections from file
      def extract_managed_sections(file_path)
        return [] unless File.exist?(file_path)

        sections = []
        current_section = nil
        line_number = 0

        File.readlines(file_path).each do |line|
          line_number += 1
          line_stripped = line.strip

          # Detect section start
          if line_stripped.include?('START: Vagrant SSH Config Manager')
            current_section = {
              start_line: line_number,
              lines: [line],
              type: :managed_section
            }
          elsif current_section
            current_section[:lines] << line

            # Detect section end
            if line_stripped.include?('END: Vagrant SSH Config Manager')
              current_section[:end_line] = line_number
              sections << current_section
              current_section = nil
            end
          end
        end

        sections
      rescue StandardError => e
        @logger.warn("Failed to extract managed sections from #{file_path}: #{e.message}")
        []
      end

      # Validate comment markers integrity
      def validate_comment_markers(file_path)
        return { valid: true, issues: [] } unless File.exist?(file_path)

        issues = []
        sections = extract_managed_sections(file_path)

        sections.each do |section|
          # Check for orphaned start markers (no matching end)
          if section[:end_line].nil?
            issues << {
              type: :orphaned_start,
              line: section[:start_line],
              message: 'Found start marker without matching end marker'
            }
          end

          # Check for corrupted section content
          section_content = section[:lines].join
          next if section_content.include?("Project: #{@project_name}")

          issues << {
            type: :corrupted_metadata,
            line: section[:start_line],
            message: 'Section metadata appears corrupted or modified'
          }
        end

        {
          valid: issues.empty?,
          issues: issues,
          sections_count: sections.length
        }
      end

      # Clean up orphaned or corrupted markers
      def cleanup_comment_markers?(file_path)
        return false unless File.exist?(file_path)

        lines = File.readlines(file_path)
        cleaned_lines = []
        skip_until_end = false
        cleaned_count = 0

        lines.each do |line|
          line_stripped = line.strip

          # Handle orphaned start markers
          # Check if this is our project
          if line_stripped.include?('START: Vagrant SSH Config Manager') && line_stripped.include?("Project: #{@project_name}")
            skip_until_end = true
            cleaned_count += 1
            next
          end

          # Handle end markers
          if skip_until_end && line_stripped.include?('END: Vagrant SSH Config Manager')
            skip_until_end = false
            next
          end

          # Keep line if not in a section being cleaned
          cleaned_lines << line unless skip_until_end
        end

        if cleaned_count.positive?
          File.write(file_path, cleaned_lines.join)
          @logger.info("Cleaned up #{cleaned_count} orphaned comment sections")
        end

        cleaned_count.positive?
      end
      alias cleanup_comment_markers cleanup_comment_markers?

      def format_comment_block(template_name, variables = {})
        template = COMMENT_TEMPLATES[template_name]
        return [] unless template

        template.map do |line|
          formatted_line = line.dup
          variables.each do |key, value|
            formatted_line.gsub!("%{#{key}}", value.to_s)
          end
          formatted_line
        end
      end

      def get_option_comment(key, value)
        case key
        when 'StrictHostKeyChecking'
          value == 'no' ? 'Skip host key verification for Vagrant VMs' : nil
        when 'UserKnownHostsFile'
          value == File::NULL ? 'Ignore known hosts for Vagrant VMs' : nil
        when 'PasswordAuthentication'
          value == 'no' ? 'Use key-based authentication only' : nil
        when 'LogLevel'
          value == 'FATAL' ? 'Minimize SSH logging output' : nil
        when 'IdentitiesOnly'
          value == 'yes' ? 'Use only specified identity file' : nil
        end
      end

      # Update existing methods to use comment markers
      def format_ssh_config_entry(ssh_config_data)
        machine_name = @machine.name.to_s
        marked_entry = add_comment_markers_to_entry(ssh_config_data, machine_name)
        marked_entry['formatted_content']
      end

      def write_multiple_entries_to_include_file(ssh_entries)
        content_lines = []

        # Add file header with comprehensive markers
        content_lines.concat(generate_file_header_with_markers)
        content_lines << ''
        content_lines.concat(add_warning_markers)
        content_lines << ''
        content_lines << "# Total entries: #{ssh_entries.length}"
        content_lines << ''

        ssh_entries.each_with_index do |ssh_config_data, index|
          next unless ssh_config_data && ssh_config_data['Host']

          # Add separator between entries
          content_lines << '' if index.positive?

          # Add entry with comment markers
          machine_name = extract_machine_name_from_host(ssh_config_data['Host'])
          marked_entry = add_comment_markers_to_entry(ssh_config_data, machine_name)
          content_lines << marked_entry['formatted_content']
        end

        content_lines << ''
        content_lines << '# End of Vagrant SSH Config Manager entries'

        # Write the include file
        File.write(@include_file_path, content_lines.join("\n"))
        File.chmod(0o600, @include_file_path)

        @logger.debug("Wrote #{ssh_entries.length} SSH entries with comment markers to: #{@include_file_path}")
      end

      # Override the include directive addition to use markers
      def add_include_directive_with_validation
        # Read existing content
        existing_content = File.exist?(@ssh_config_file) ? File.read(@ssh_config_file) : ''

        # Check if our include directive already exists
        return true if existing_content.include?("Include #{@include_file_path}")

        # Find the best place to insert the include directive
        lines = existing_content.lines
        insert_position = find_include_insert_position(lines)

        # Generate include directive with markers
        include_lines = generate_include_directive_with_markers

        # Insert at the determined position
        new_lines = lines.dup
        include_lines.reverse.each do |line|
          new_lines.insert(insert_position, "#{line}\n")
        end

        # Write updated content
        File.write(@ssh_config_file, new_lines.join)

        @logger.debug("Added include directive with markers to SSH config file at position #{insert_position}")
      end

      def remove_from_include_file(host_name)
        return false unless File.exist?(@include_file_path)

        lines = File.readlines(@include_file_path)
        new_lines = []
        skip_until_next_host = false
        removed = false

        lines.each do |line|
          line_stripped = line.strip

          if line_stripped.start_with?('Host ')
            current_host = line_stripped.sub(/^Host\s+/, '')
            if current_host == host_name
              skip_until_next_host = true
              removed = true
              next
            else
              skip_until_next_host = false
            end
          end

          new_lines << line unless skip_until_next_host
        end

        if removed
          File.write(@include_file_path, new_lines.join)
          @logger.debug("Removed host #{host_name} from include file")
        end

        removed
      end

      def cleanup_empty_include_file
        return unless File.exist?(@include_file_path)

        content = File.read(@include_file_path).strip
        # Remove file if it only contains comments or is empty
        return unless content.empty? || content.lines.all? { |line| line.strip.empty? || line.strip.start_with?('#') }

        File.delete(@include_file_path)
        @logger.debug("Removed empty include file: #{@include_file_path}")
      end

      def cleanup_include_directive_if_needed
        return unless File.exist?(@ssh_config_file)
        return if File.exist?(@include_file_path) # Don't remove if include file still exists

        lines = File.readlines(@ssh_config_file)
        new_lines = lines.reject do |line|
          ["Include #{@include_file_path}", '# Vagrant SSH Config Manager - Include'].include?(line.strip)
        end

        return unless new_lines.length != lines.length

        File.write(@ssh_config_file, new_lines.join)
        @logger.debug('Removed include directive from SSH config file')
      end

      def backup_main_config
        return nil unless File.exist?(@ssh_config_file)

        backup_path = "#{@ssh_config_file}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        FileUtils.cp(@ssh_config_file, backup_path)

        @logger.debug("Created backup of main SSH config: #{backup_path}")
        backup_path
      rescue StandardError => e
        @logger.warn("Failed to create main config backup: #{e.message}")
        nil
      end

      def remove_include_directive_with_validation
        return false unless File.exist?(@ssh_config_file)

        lines = File.readlines(@ssh_config_file)
        new_lines = []
        skip_next_empty = false

        lines.each do |line|
          line_stripped = line.strip

          # Skip our include directive and its comment
          if ["Include #{@include_file_path}",
              '# Vagrant SSH Config Manager - Auto-generated include'].include?(line_stripped)
            skip_next_empty = true
            next
          end

          # Skip the empty line after our include directive
          if skip_next_empty && line_stripped.empty?
            skip_next_empty = false
            next
          end

          skip_next_empty = false
          new_lines << line
        end

        File.write(@ssh_config_file, new_lines.join)
        @logger.debug('Removed include directive from SSH config file')
      end

      def find_include_insert_position(lines)
        # Try to find existing Include directives and insert after them
        last_include_position = -1

        lines.each_with_index do |line, index|
          last_include_position = index if line.strip.start_with?('Include ')
        end

        # If we found includes, insert after the last one
        return last_include_position + 1 if last_include_position >= 0

        # Otherwise, insert at the beginning (after any initial comments)
        lines.each_with_index do |line, index|
          line_stripped = line.strip
          return index unless line_stripped.empty? || line_stripped.start_with?('#')
        end

        # If file is empty or only comments, insert at the end
        lines.length
      end

      def find_host_in_file(file_path, host_name, source_description)
        conflicts = []
        return conflicts unless File.exist?(file_path)

        line_number = 0
        File.readlines(file_path).each do |line|
          line_number += 1
          line_stripped = line.strip

          next unless line_stripped.start_with?('Host ') && line_stripped.include?(host_name)

          conflicts << {
            file: file_path,
            source: source_description,
            line_number: line_number,
            line_content: line_stripped
          }
        end

        conflicts
      rescue StandardError => e
        @logger.warn("Failed to search for host conflicts in #{file_path}: #{e.message}")
        []
      end
    end
  end
end
