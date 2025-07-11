# frozen_string_literal: true

require 'fcntl'
require 'timeout'

module VagrantPlugins
  module SshConfigManager
    # Handles file locking for SSH config files to prevent concurrent conflicts
    class FileLocker
      # Default timeout for acquiring locks (in seconds)
      DEFAULT_TIMEOUT = 30

      # Lock types
      LOCK_SHARED = File::LOCK_SH
      LOCK_EXCLUSIVE = File::LOCK_EX
      LOCK_NON_BLOCKING = File::LOCK_NB

      def initialize(file_path, logger = nil)
        @file_path = file_path
        @logger = logger || Log4r::Logger.new('vagrant::plugins::ssh_config_manager::file_locker')
        @lock_file = nil
        @locked = false
      end

      # Acquire an exclusive lock on the file
      def with_exclusive_lock(timeout: DEFAULT_TIMEOUT, &block)
        with_lock(LOCK_EXCLUSIVE, timeout: timeout, &block)
      end

      # Acquire a shared lock on the file
      def with_shared_lock(timeout: DEFAULT_TIMEOUT, &block)
        with_lock(LOCK_SHARED, timeout: timeout, &block)
      end

      # Check if file is currently locked by another process
      def locked?
        return false unless File.exist?(@file_path)

        begin
          File.open(@file_path, 'r') do |file|
            # Try to acquire a non-blocking exclusive lock
            file.flock(LOCK_EXCLUSIVE | LOCK_NON_BLOCKING)
            false # Not locked if we could acquire the lock
          end
        rescue Errno::EAGAIN, Errno::EACCES
          true # File is locked
        rescue StandardError => e
          @logger.debug("Error checking lock status: #{e.message}")
          false
        end
      end

      private

      def with_lock(lock_type, timeout: DEFAULT_TIMEOUT)
        acquire_lock(lock_type, timeout: timeout)

        begin
          yield
        ensure
          release_lock
        end
      end

      def acquire_lock(lock_type, timeout: DEFAULT_TIMEOUT)
        ensure_directory_exists

        @logger.debug("Acquiring #{lock_type_name(lock_type)} lock on #{@file_path}")

        # Use timeout to prevent infinite waiting
        Timeout.timeout(timeout) do
          @lock_file = File.open(@file_path, File::RDWR | File::CREAT, 0o600)
          @lock_file.flock(lock_type)
          @locked = true
          @logger.debug("Successfully acquired lock on #{@file_path}")
        end
      rescue Timeout::Error
        cleanup_lock_file
        raise LockTimeoutError, "Timeout waiting for lock on #{@file_path} (waited #{timeout}s)"
      rescue StandardError => e
        cleanup_lock_file
        @logger.error("Failed to acquire lock on #{@file_path}: #{e.message}")
        raise LockAcquisitionError, "Could not acquire lock: #{e.message}"
      end

      def release_lock
        return unless @locked && @lock_file

        @logger.debug("Releasing lock on #{@file_path}")

        begin
          @lock_file.flock(File::LOCK_UN)
        rescue StandardError => e
          @logger.warn("Error releasing lock: #{e.message}")
        ensure
          cleanup_lock_file
        end
      end

      def cleanup_lock_file
        return unless @lock_file

        begin
          @lock_file.close unless @lock_file.closed?
        rescue StandardError => e
          @logger.debug("Error closing lock file: #{e.message}")
        ensure
          @lock_file = nil
          @locked = false
        end
      end

      def ensure_directory_exists
        dir = File.dirname(@file_path)
        return if File.directory?(dir)

        FileUtils.mkdir_p(dir, mode: 0o700)
        @logger.debug("Created directory: #{dir}")
      end

      def lock_type_name(lock_type)
        case lock_type
        when LOCK_SHARED
          'shared'
        when LOCK_EXCLUSIVE
          'exclusive'
        else
          'unknown'
        end
      end
    end

    # Custom exception classes
    class LockError < StandardError; end
    class LockTimeoutError < LockError; end
    class LockAcquisitionError < LockError; end
  end
end
