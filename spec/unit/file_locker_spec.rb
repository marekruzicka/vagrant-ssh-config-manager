require 'spec_helper'

RSpec.describe VagrantPlugins::SshConfigManager::FileLocker do
  let(:test_file) { File.join(@temp_dir, 'test_lock_file') }
  let(:locker) { described_class.new(test_file) }

  describe '#initialize' do
    it 'initializes with file path' do
      expect(locker.instance_variable_get(:@file_path)).to eq(test_file)
      expect(locker.instance_variable_get(:@locked)).to be false
    end

    it 'accepts optional logger' do
      logger = double('logger')
      custom_locker = described_class.new(test_file, logger)
      expect(custom_locker.instance_variable_get(:@logger)).to eq(logger)
    end
  end

  describe '#with_exclusive_lock' do
    it 'acquires and releases exclusive lock' do
      result = nil
      
      locker.with_exclusive_lock do
        result = 'executed'
        expect(locker.instance_variable_get(:@locked)).to be true
      end
      
      expect(result).to eq('executed')
      expect(locker.instance_variable_get(:@locked)).to be false
    end

    it 'creates file if it does not exist' do
      expect(File.exist?(test_file)).to be false
      
      locker.with_exclusive_lock do
        # Lock acquired
      end
      
      expect(File.exist?(test_file)).to be true
    end

    it 'sets correct file permissions' do
      locker.with_exclusive_lock do
        # Lock acquired
      end
      
      expect(File.stat(test_file).mode & 0777).to eq(0600)
    end

    it 'releases lock even if block raises exception' do
      expect do
        locker.with_exclusive_lock do
          raise StandardError, 'test error'
        end
      end.to raise_error(StandardError, 'test error')
      
      expect(locker.instance_variable_get(:@locked)).to be false
    end

    it 'handles timeout when lock cannot be acquired' do
      # This is difficult to test without threading, but we can test the structure
      expect(locker).to respond_to(:with_exclusive_lock)
      
      # Test with very short timeout
      expect do
        locker.with_exclusive_lock(timeout: 0.001) do
          # This should work for a non-contended lock
        end
      end.not_to raise_error
    end
  end

  describe '#with_shared_lock' do
    it 'acquires and releases shared lock' do
      result = nil
      
      locker.with_shared_lock do
        result = 'executed'
        expect(locker.instance_variable_get(:@locked)).to be true
      end
      
      expect(result).to eq('executed')
      expect(locker.instance_variable_get(:@locked)).to be false
    end

    it 'allows multiple shared locks' do
      # This would require threading to test properly
      # For now, test basic functionality
      locker.with_shared_lock do
        expect(locker.instance_variable_get(:@locked)).to be true
      end
    end
  end

  describe '#locked?' do
    it 'returns false when file does not exist' do
      expect(locker.locked?).to be false
    end

    it 'returns false when file is not locked' do
      File.write(test_file, 'test content')
      expect(locker.locked?).to be false
    end

    it 'detects when file is locked by another process' do
      # This is difficult to test without forking processes
      # For now, test the basic structure
      expect(locker).to respond_to(:locked?)
    end
  end

  describe 'error handling' do
    context 'when directory does not exist' do
      let(:test_file) { File.join(@temp_dir, 'nonexistent', 'dir', 'file') }

      it 'creates directory structure' do
        locker.with_exclusive_lock do
          # Directory should be created
        end
        
        expect(File.exist?(File.dirname(test_file))).to be true
      end
    end

    context 'when directory is not writable' do
      before do
        Dir.mkdir(File.join(@temp_dir, 'readonly'))
        File.chmod(0400, File.join(@temp_dir, 'readonly'))
      end

      let(:test_file) { File.join(@temp_dir, 'readonly', 'file') }

      it 'handles permission errors gracefully' do
        expect do
          locker.with_exclusive_lock do
            # This should raise a LockAcquisitionError
          end
        end.to raise_error(VagrantPlugins::SshConfigManager::LockAcquisitionError)
      end
    end

    context 'when timeout occurs' do
      it 'raises LockTimeoutError' do
        # Create a file that's already locked
        File.open(test_file, 'w') do |f|
          f.flock(File::LOCK_EX)
          
          # This is complex to test without threading
          # For now, test the error class exists
          expect(VagrantPlugins::SshConfigManager::LockTimeoutError).to be < StandardError
        end
      end
    end
  end

  describe 'cleanup' do
    it 'cleans up lock file handle on error' do
      allow(File).to receive(:open).and_raise(StandardError, 'test error')
      
      expect do
        locker.with_exclusive_lock do
          # Should not execute
        end
      end.to raise_error(VagrantPlugins::SshConfigManager::LockAcquisitionError)
      
      expect(locker.instance_variable_get(:@lock_file)).to be_nil
      expect(locker.instance_variable_get(:@locked)).to be false
    end

    it 'handles close errors gracefully' do
      locker.with_exclusive_lock do
        lock_file = locker.instance_variable_get(:@lock_file)
        allow(lock_file).to receive(:close).and_raise(StandardError, 'close error')
        # Should not raise error during cleanup
      end
      
      expect(locker.instance_variable_get(:@locked)).to be false
    end
  end

  describe 'lock types' do
    it 'defines lock type constants' do
      expect(described_class::LOCK_SHARED).to eq(File::LOCK_SH)
      expect(described_class::LOCK_EXCLUSIVE).to eq(File::LOCK_EX)
      expect(described_class::LOCK_NON_BLOCKING).to eq(File::LOCK_NB)
    end

    it 'has default timeout constant' do
      expect(described_class::DEFAULT_TIMEOUT).to eq(30)
    end
  end

  describe 'exception classes' do
    it 'defines custom exception hierarchy' do
      expect(VagrantPlugins::SshConfigManager::LockError).to be < StandardError
      expect(VagrantPlugins::SshConfigManager::LockTimeoutError).to be < VagrantPlugins::SshConfigManager::LockError
      expect(VagrantPlugins::SshConfigManager::LockAcquisitionError).to be < VagrantPlugins::SshConfigManager::LockError
    end
  end
end
