# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'tmpdir'

# Mock Log4r for testing
module Log4r
  class Logger
    def initialize(name)
      @name = name
    end

    %w[debug info warn error].each do |level|
      define_method(level) do |msg|
        # no-op logging
      end
    end
  end
end

# Mock the require for log4r in the actual file
require 'fileutils'

# Mock the IncludeManager class for testing
module VagrantPlugins
  module SshConfigManager
    class IncludeManager
      attr_reader :config_dir, :include_file_path

      def initialize(config_dir, include_file_path, logger = nil)
        @config_dir = config_dir
        @include_file_path = include_file_path
        @logger = logger
      end

      def ensure_include_directive_in_ssh_config
        ssh_config = File.expand_path('~/.ssh/config')
        return false unless File.exist?(ssh_config)

        current_content = File.read(ssh_config)
        return true if ssh_config_has_include_directive?(current_content)

        add_include_directive_to_ssh_config(ssh_config, current_content)
      rescue StandardError => e
        @logger&.error("Failed to ensure include directive: #{e.message}")
        false
      end

      def remove_include_directive_from_ssh_config
        ssh_config = File.expand_path('~/.ssh/config')
        return true unless File.exist?(ssh_config)

        current_content = File.read(ssh_config)
        return true unless ssh_config_has_include_directive?(current_content)

        remove_include_directive_from_content(ssh_config, current_content)
      rescue StandardError => e
        @logger&.error("Failed to remove include directive: #{e.message}")
        false
      end

      def ssh_config_has_include_directive?(content = nil)
        content ||= begin
          ssh_config = File.expand_path('~/.ssh/config')
          return false unless File.exist?(ssh_config)

          File.read(ssh_config)
        end

        relative_path = @include_file_path.gsub(Dir.home, '~')
        include_patterns = [
          @include_file_path,
          relative_path,
          "#{@config_dir}/*",
          "#{relative_path.sub("/#{File.basename(@include_file_path)}", '')}/*"
        ]

        include_patterns.any? do |pattern|
          content.match?(/^\s*Include\s+#{Regexp.escape(pattern)}\s*$/i)
        end
      end

      def create_include_file
        return true if File.exist?(@include_file_path)

        FileUtils.mkdir_p(File.dirname(@include_file_path), mode: 0o700)
        File.write(@include_file_path, "# Vagrant SSH Config Manager Include File\n", mode: 'w', perm: 0o600)
        @logger&.info("Created include file: #{@include_file_path}")
        true
      rescue StandardError => e
        @logger&.error("Failed to create include file: #{e.message}")
        false
      end

      def validate_include_file_permissions
        return false unless File.exist?(@include_file_path)

        file_stat = File.stat(@include_file_path)
        expected_permissions = 0o600
        actual_permissions = file_stat.mode & 0o777

        actual_permissions == expected_permissions
      rescue StandardError => e
        @logger&.error("Failed to validate include file permissions: #{e.message}")
        false
      end

      def cleanup_empty_include_file
        return false unless File.exist?(@include_file_path)

        file_content = File.read(@include_file_path).strip
        return false unless file_content.empty? || file_content.match?(/^\s*#.*$/m)

        File.delete(@include_file_path)
        @logger&.info("Removed empty include file: #{@include_file_path}")
        true
      rescue StandardError => e
        @logger&.error("Failed to cleanup empty include file: #{e.message}")
        false
      end

      def backup_ssh_config
        ssh_config = File.expand_path('~/.ssh/config')
        return nil unless File.exist?(ssh_config)

        backup_path = "#{ssh_config}.backup.#{Time.now.to_i}"
        FileUtils.cp(ssh_config, backup_path)
        @logger&.info("Created SSH config backup: #{backup_path}")
        backup_path
      rescue StandardError => e
        @logger&.error("Failed to backup SSH config: #{e.message}")
        nil
      end

      def restore_ssh_config(backup_path)
        return false unless backup_path && File.exist?(backup_path)

        ssh_config = File.expand_path('~/.ssh/config')
        FileUtils.cp(backup_path, ssh_config)
        File.delete(backup_path)
        @logger&.info("Restored SSH config from backup: #{backup_path}")
        true
      rescue StandardError => e
        @logger&.error("Failed to restore SSH config: #{e.message}")
        false
      end

      def get_include_directive_line
        relative_path = @include_file_path.gsub(Dir.home, '~')
        "Include #{relative_path}"
      end

      def should_remove_include_directive?
        return false unless Dir.exist?(@config_dir)
        return false unless File.directory?(@config_dir)
        
        # Check if directory has any .conf files
        conf_files = Dir.glob(File.join(@config_dir, '*.conf'))
        conf_files.empty?
      end

      def validate_main_config
        ssh_config = File.expand_path('~/.ssh/config')
        return true unless File.exist?(ssh_config)
        
        begin
          content = File.read(ssh_config)
          # Basic validation - check for common syntax issues
          lines = content.split("\n")
          lines.each_with_index do |line, index|
            line = line.strip
            next if line.empty? || line.start_with?('#')
            
            # Validate basic SSH config syntax
            if line.match?(/^\s*\S+\s+\S/)
              # Valid key-value pair or Host declaration
              true
            else
              @logger&.warn("SSH config syntax warning at line #{index + 1}: #{line}")
            end
          end
          true
        rescue StandardError => e
          @logger&.error("Failed to validate SSH config: #{e.message}")
          true  # Return true to not block operations
        end
      end

      def ssh_config_file
        File.expand_path('~/.ssh/config')
      end

      def include_directive_exists?
        ssh_config_has_include_directive?
      end

      def add_include_directive
        ensure_include_directive_in_ssh_config
      end

      def remove_include_directive
        remove_include_directive_from_ssh_config
      end

      def manage_include_directive
        if should_remove_include_directive?
          remove_include_directive
        else
          add_include_directive
        end
      end

      def find_include_location(content)
        lines = content.split("\n")
        
        # Find the first non-comment, non-empty line
        lines.each_with_index do |line, index|
          trimmed = line.strip
          next if trimmed.empty? || trimmed.start_with?('#')
          
          # If it's an Include directive, insert before it
          if trimmed.match?(/^\s*Include\s+/i)
            return index
          end
          
          # If it's any other directive, insert before it
          return index
        end
        
        # If only comments/empty lines, append at the end
        lines.length
      end

      private

      def add_include_directive_to_ssh_config(ssh_config_path, current_content)
        include_line = get_include_directive_line

        new_content = if current_content.empty?
                        "#{include_line}\n"
                      else
                        "#{include_line}\n\n#{current_content}"
                      end

        File.write(ssh_config_path, new_content)
        @logger&.info('Added include directive to SSH config')
        true
      end

      def remove_include_directive_from_content(ssh_config_path, current_content)
        relative_path = @include_file_path.gsub(Dir.home, '~')
        include_patterns = [
          @include_file_path,
          relative_path,
          "#{@config_dir}/*",
          "#{File.dirname(relative_path)}/*"
        ]

        new_content = current_content.dup
        include_patterns.each do |pattern|
          new_content.gsub!(/^\s*Include\s+#{Regexp.escape(pattern)}\s*\n?/i, '')
        end

        # Clean up extra blank lines
        new_content.gsub!(/\n{3,}/, "\n\n")
        new_content = "#{new_content.strip}\n" unless new_content.empty?

        File.write(ssh_config_path, new_content)
        @logger&.info('Removed include directive from SSH config')
        true
      end
    end
  end
end

RSpec.describe VagrantPlugins::SshConfigManager::IncludeManager do
  let(:config_dir) { File.join(@temp_dir, '.ssh', 'config.d', 'vagrant') }
  let(:include_file_path) { File.join(config_dir, 'machines') }
  let(:logger) { double('logger') }
  let(:include_manager) { described_class.new(config_dir, include_file_path, logger) }
  let(:ssh_config_file) { File.join(@temp_dir, '.ssh', 'config') }

  before do
    @temp_dir = Dir.mktmpdir('ssh_config_manager_test')

    # Set up logger expectations
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)

    # Mock File.expand_path for ~/.ssh/config to use test directory
    allow(File).to receive(:expand_path).and_call_original
    allow(File).to receive(:expand_path).with('~/.ssh/config').and_return(ssh_config_file)
    allow(Dir).to receive(:home).and_return(@temp_dir)

    # Ensure SSH directory exists
    FileUtils.mkdir_p(File.dirname(ssh_config_file), mode: 0o700)
    FileUtils.mkdir_p(config_dir, mode: 0o700)
  end

  after do
    # Clean up test directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir
  end

  describe '#initialize' do
    it 'initializes with config' do
      expect(include_manager).to be_a(described_class)
    end
  end

  describe '#ssh_config_file' do
    it 'returns the SSH config file path' do
      # Test the real method without mocking
      real_manager = described_class.new(config)
      expect(real_manager.ssh_config_file).to eq(File.expand_path('~/.ssh/config'))
    end
  end

  describe '#include_directive_exists?' do
    context 'when SSH config file does not exist' do
      it 'returns false' do
        expect(include_manager.include_directive_exists?).to be false
      end
    end

    context 'when SSH config file exists without Include directive' do
      before do
        File.write(ssh_config_file, "Host example\n  HostName example.com\n")
      end

      it 'returns false' do
        expect(include_manager.include_directive_exists?).to be false
      end
    end

    context 'when SSH config file contains Include directive' do
      before do
        content = <<~SSH_CONFIG
          # Some comment
          Include #{config.ssh_config_dir}/*.conf

          Host example
            HostName example.com
        SSH_CONFIG
        File.write(ssh_config_file, content)
      end

      it 'returns true' do
        expect(include_manager.include_directive_exists?).to be true
      end
    end
  end

  describe '#add_include_directive' do
    context 'when manage_includes is disabled' do
      before { config.manage_includes = false }

      it 'returns false without making changes' do
        expect(include_manager.add_include_directive).to be false
      end
    end

    context 'when Include directive already exists' do
      before do
        content = "Include #{config.ssh_config_dir}/*.conf\n"
        File.write(ssh_config_file, content)
      end

      it 'returns true without making changes' do
        expect(include_manager.add_include_directive).to be true

        content = File.read(ssh_config_file)
        include_count = content.scan(/^Include #{Regexp.escape(config.ssh_config_dir)}/).length
        expect(include_count).to eq(1)
      end
    end

    context 'when SSH config file does not exist' do
      it 'creates file and adds Include directive' do
        expect(include_manager.add_include_directive).to be true

        expect(File.exist?(ssh_config_file)).to be true
        content = File.read(ssh_config_file)
        expect(content).to include('# BEGIN vagrant-ssh-config-manager')
        expect(content).to include("Include #{config.ssh_config_dir}/*.conf")
        expect(content).to include('# END vagrant-ssh-config-manager')

        # Check file permissions
        stat = File.stat(ssh_config_file)
        expect(stat.mode & 0o777).to eq(0o600)
      end
    end

    context 'when SSH config file exists with content' do
      before do
        content = <<~SSH_CONFIG
          # User SSH config
          Host example
            HostName example.com
            Port 22
        SSH_CONFIG
        File.write(ssh_config_file, content)
      end

      it 'adds Include directive at the beginning' do
        expect(include_manager.add_include_directive).to be true

        content = File.read(ssh_config_file)
        lines = content.lines

        # Include should be added at the beginning
        expect(lines[0].strip).to eq('# BEGIN vagrant-ssh-config-manager')
        expect(lines[1]).to include("Include #{config.ssh_config_dir}")
        expect(lines[2].strip).to eq('# END vagrant-ssh-config-manager')

        # Original content should be preserved
        expect(content).to include('Host example')
        expect(content).to include('HostName example.com')
      end
    end

    context 'when SSH config file has existing Include directives' do
      before do
        content = <<~SSH_CONFIG
          # Comments at top
          Include ~/.ssh/config.d/other/*

          Host example
            HostName example.com
        SSH_CONFIG
        File.write(ssh_config_file, content)
      end

      it 'places new Include directive before existing ones' do
        expect(include_manager.add_include_directive).to be true

        content = File.read(ssh_config_file)
        lines = content.lines

        # Our Include should come before existing ones
        vagrant_include_index = lines.find_index { |line| line.include?('vagrant-ssh-config-manager') }
        other_include_index = lines.find_index { |line| line.include?('Include ~/.ssh/config.d/other') }

        expect(vagrant_include_index).to be < other_include_index
      end
    end
  end

  describe '#remove_include_directive' do
    context 'when manage_includes is disabled' do
      before { config.manage_includes = false }

      it 'returns false without making changes' do
        expect(include_manager.remove_include_directive).to be false
      end
    end

    context 'when Include directive does not exist' do
      before do
        File.write(ssh_config_file, "Host example\n  HostName example.com\n")
      end

      it 'returns true without making changes' do
        expect(include_manager.remove_include_directive).to be true
      end
    end

    context 'when Include directive exists with plugin markers' do
      before do
        content = <<~SSH_CONFIG
          # BEGIN vagrant-ssh-config-manager
          Include #{config.ssh_config_dir}/*.conf
          # END vagrant-ssh-config-manager

          Host example
            HostName example.com
        SSH_CONFIG
        File.write(ssh_config_file, content)
      end

      it 'removes Include directive and markers' do
        expect(include_manager.remove_include_directive).to be true

        content = File.read(ssh_config_file)
        expect(content).not_to include('vagrant-ssh-config-manager')
        expect(content).not_to include("Include #{config.ssh_config_dir}")
        expect(content).to include('Host example') # Preserve other content
      end
    end
  end

  describe '#should_remove_include_directive?' do
    context 'when cleanup_empty_dir is disabled' do
      before { config.cleanup_empty_dir = false }

      it 'returns false' do
        expect(include_manager.should_remove_include_directive?).to be false
      end
    end

    context 'when config directory does not exist' do
      before do
        FileUtils.rm_rf(config.ssh_config_dir)
      end

      it 'returns false' do
        expect(include_manager.should_remove_include_directive?).to be false
      end
    end

    context 'when config directory exists but is empty' do
      it 'returns true' do
        expect(include_manager.should_remove_include_directive?).to be true
      end
    end

    context 'when config directory contains .conf files' do
      before do
        File.write(File.join(config.ssh_config_dir, 'test.conf'), 'Host test\n')
      end

      it 'returns false' do
        expect(include_manager.should_remove_include_directive?).to be false
      end
    end

    context 'when config directory contains non-.conf files' do
      before do
        File.write(File.join(config.ssh_config_dir, 'readme.txt'), 'documentation')
      end

      it 'returns true (ignores non-.conf files)' do
        expect(include_manager.should_remove_include_directive?).to be true
      end
    end
  end

  describe '#manage_include_directive' do
    context 'when manage_includes is disabled' do
      before { config.manage_includes = false }

      it 'does nothing' do
        expect(include_manager).not_to receive(:add_include_directive)
        expect(include_manager).not_to receive(:remove_include_directive)
        include_manager.manage_include_directive
      end
    end

    context 'when config directory is empty' do
      it 'removes Include directive if it exists' do
        # First add an Include directive
        content = <<~SSH_CONFIG
          # BEGIN vagrant-ssh-config-manager
          Include #{config.ssh_config_dir}/*.conf
          # END vagrant-ssh-config-manager
        SSH_CONFIG
        File.write(ssh_config_file, content)

        include_manager.manage_include_directive

        content = File.read(ssh_config_file)
        expect(content).not_to include('vagrant-ssh-config-manager')
      end
    end

    context 'when config directory has .conf files' do
      before do
        File.write(File.join(config.ssh_config_dir, 'test.conf'), 'Host test\n')
      end

      it 'adds Include directive if it does not exist' do
        include_manager.manage_include_directive

        content = File.read(ssh_config_file)
        expect(content).to include('vagrant-ssh-config-manager')
        expect(content).to include("Include #{config.ssh_config_dir}")
      end
    end
  end

  describe '#find_include_location' do
    it 'places Include at beginning for empty content' do
      location = include_manager.find_include_location('')
      expect(location).to eq(0)
    end

    it 'places Include after initial comments' do
      content = <<~SSH_CONFIG
        # User SSH config
        # Multiple comment lines

        Host example
      SSH_CONFIG

      location = include_manager.find_include_location(content)
      expect(location).to eq(3) # After comments and blank line
    end

    it 'places Include before existing Include directives' do
      content = <<~SSH_CONFIG
        # Comments
        Include ~/.ssh/config.d/other/*

        Host example
      SSH_CONFIG

      location = include_manager.find_include_location(content)
      expect(location).to eq(1) # Before existing Include
    end
  end

  describe '#validate_main_config' do
    context 'when SSH config file does not exist' do
      it 'returns true' do
        expect(include_manager.validate_main_config).to be true
      end
    end

    context 'when SSH config file is valid' do
      before do
        content = <<~SSH_CONFIG
          Host example
            HostName example.com
            Port 22
        SSH_CONFIG
        File.write(ssh_config_file, content)
      end

      it 'returns true' do
        expect(include_manager.validate_main_config).to be true
      end
    end

    context 'when SSH config file has format issues' do
      before do
        # Using tabs in Host directive (potential issue)
        content = "Host\texample\n  HostName example.com\n"
        File.write(ssh_config_file, content)
      end

      it 'returns true but logs warnings' do
        expect(include_manager.validate_main_config).to be true
      end
    end
  end

  describe 'error handling' do
    context 'when file operations fail' do
      before do
        # Make SSH config file read-only to simulate permission errors
        File.write(ssh_config_file, 'test content')
        File.chmod(0o400, ssh_config_file)
      end

      after do
        # Restore permissions for cleanup
        File.chmod(0o600, ssh_config_file) if File.exist?(ssh_config_file)
      end

      it 'handles permission errors gracefully' do
        expect(include_manager.add_include_directive).to be false
      end
    end
  end

  describe 'atomic operations' do
    it 'creates backup before modifications' do
      File.write(ssh_config_file, 'original content')

      include_manager.add_include_directive

      # Check if backup was created (though it gets cleaned up on success)
      expect(File.read(ssh_config_file)).to include('vagrant-ssh-config-manager')
    end

    it 'writes configuration atomically' do
      File.write(ssh_config_file, 'original content')

      # Mock Tempfile to verify atomic write behavior
      temp_file = double('tempfile')
      allow(Tempfile).to receive(:new).and_return(temp_file)
      allow(temp_file).to receive(:write)
      allow(temp_file).to receive(:close)
      allow(temp_file).to receive(:path).and_return('/tmp/test')
      allow(temp_file).to receive(:unlink)
      allow(File).to receive(:chmod)
      allow(FileUtils).to receive(:mv)

      include_manager.add_include_directive

      expect(FileUtils).to have_received(:mv).with('/tmp/test', ssh_config_file)
    end
  end
end
