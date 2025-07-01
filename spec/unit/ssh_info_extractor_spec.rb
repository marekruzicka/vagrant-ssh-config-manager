require 'spec_helper'

RSpec.describe VagrantPlugins::SshConfigManager::SshInfoExtractor do
  let(:machine) { create_mock_machine }
  let(:extractor) { described_class.new(machine) }

  describe '#initialize' do
    it 'initializes with a machine' do
      expect(extractor.instance_variable_get(:@machine)).to eq(machine)
      expect(extractor.instance_variable_get(:@logger)).not_to be_nil
    end
  end

  describe '#ssh_capable?' do
    context 'when machine has communicator' do
      it 'returns true for SSH-capable machines' do
        expect(extractor.ssh_capable?).to be true
      end
    end

    context 'when machine has no communicator' do
      before do
        allow(machine).to receive(:communicate).and_return(nil)
      end

      it 'returns false' do
        expect(extractor.ssh_capable?).to be false
      end
    end

    context 'when machine communicator is not ready' do
      before do
        communicator = double('communicator')
        allow(communicator).to receive(:ready?).and_return(false)
        allow(machine).to receive(:communicate).and_return(communicator)
      end

      it 'returns false' do
        expect(extractor.ssh_capable?).to be false
      end
    end
  end

  describe '#extract_ssh_info' do
    let(:ssh_info) do
      {
        host: '192.168.1.100',
        port: 22,
        username: 'ubuntu',
        private_key_path: ['/path/to/key1', '/path/to/key2'],
        forward_agent: true,
        compression: true
      }
    end

    before do
      allow(machine).to receive(:ssh_info).and_return(ssh_info)
    end

    it 'extracts and normalizes SSH info' do
      result = extractor.extract_ssh_info

      expect(result).to be_a(Hash)
      expect(result['HostName']).to eq('192.168.1.100')
      expect(result['Port']).to eq('22')
      expect(result['User']).to eq('ubuntu')
      expect(result['IdentityFile']).to eq('/path/to/key1')
    end

    it 'handles multiple private keys by using the first one' do
      result = extractor.extract_ssh_info
      expect(result['IdentityFile']).to eq('/path/to/key1')
    end

    it 'sets ForwardAgent when enabled' do
      result = extractor.extract_ssh_info
      expect(result['ForwardAgent']).to eq('yes')
    end

    it 'sets Compression when enabled' do
      result = extractor.extract_ssh_info
      expect(result['Compression']).to eq('yes')
    end

    context 'with default SSH port' do
      let(:ssh_info) { { host: '127.0.0.1', port: 22, username: 'vagrant' } }

      it 'includes port 22 explicitly' do
        result = extractor.extract_ssh_info
        expect(result['Port']).to eq('22')
      end
    end

    context 'with custom SSH port' do
      let(:ssh_info) { { host: '127.0.0.1', port: 2222, username: 'vagrant' } }

      it 'includes custom port' do
        result = extractor.extract_ssh_info
        expect(result['Port']).to eq('2222')
      end
    end

    context 'with proxy command' do
      let(:ssh_info) do
        {
          host: '10.0.0.1',
          port: 22,
          username: 'user',
          proxy_command: 'ssh -W %h:%p jump-host'
        }
      end

      it 'includes proxy command' do
        result = extractor.extract_ssh_info
        expect(result['ProxyCommand']).to eq('ssh -W %h:%p jump-host')
      end
    end

    context 'with additional SSH options' do
      let(:ssh_info) do
        {
          host: '127.0.0.1',
          port: 22,
          username: 'vagrant',
          keys_only: true,
          paranoid: false,
          config: false
        }
      end

      it 'includes additional SSH options' do
        result = extractor.extract_ssh_info
        
        expect(result['IdentitiesOnly']).to eq('yes')
        expect(result['StrictHostKeyChecking']).to eq('no')
        expect(result['UserKnownHostsFile']).to eq('/dev/null')
      end
    end

    context 'when SSH info is nil' do
      before do
        allow(machine).to receive(:ssh_info).and_return(nil)
      end

      it 'returns nil' do
        expect(extractor.extract_ssh_info).to be_nil
      end
    end

    context 'when SSH info is empty' do
      before do
        allow(machine).to receive(:ssh_info).and_return({})
      end

      it 'returns nil' do
        expect(extractor.extract_ssh_info).to be_nil
      end
    end

    context 'when SSH info is missing required fields' do
      let(:incomplete_ssh_info) { { port: 22 } }

      before do
        allow(machine).to receive(:ssh_info).and_return(incomplete_ssh_info)
      end

      it 'returns nil' do
        expect(extractor.extract_ssh_info).to be_nil
      end
    end
  end

  describe '#normalize_ssh_info' do
    let(:raw_ssh_info) do
      {
        host: '192.168.1.100',
        port: 2222,
        username: 'vagrant',
        private_key_path: ['/Users/user/.vagrant.d/insecure_private_key'],
        forward_agent: false,
        compression: false,
        keys_only: true,
        paranoid: false
      }
    end

    it 'converts raw SSH info to SSH config format' do
      result = extractor.send(:normalize_ssh_info, raw_ssh_info)

      expect(result['HostName']).to eq('192.168.1.100')
      expect(result['Port']).to eq('2222')
      expect(result['User']).to eq('vagrant')
      expect(result['IdentityFile']).to eq('/Users/user/.vagrant.d/insecure_private_key')
      expect(result['ForwardAgent']).to eq('no')
      expect(result['Compression']).to eq('no')
      expect(result['IdentitiesOnly']).to eq('yes')
      expect(result['StrictHostKeyChecking']).to eq('no')
      expect(result['UserKnownHostsFile']).to eq('/dev/null')
    end

    it 'handles missing optional fields gracefully' do
      minimal_info = { host: '127.0.0.1', port: 22, username: 'test' }
      result = extractor.send(:normalize_ssh_info, minimal_info)

      expect(result['HostName']).to eq('127.0.0.1')
      expect(result['Port']).to eq('22')
      expect(result['User']).to eq('test')
      expect(result['IdentityFile']).to be_nil
    end
  end

  describe 'error handling' do
    context 'when machine.ssh_info raises an exception' do
      before do
        allow(machine).to receive(:ssh_info).and_raise(StandardError.new('SSH error'))
      end

      it 'handles the exception gracefully' do
        expect { extractor.extract_ssh_info }.not_to raise_error
        expect(extractor.extract_ssh_info).to be_nil
      end
    end

    context 'when machine.communicate raises an exception' do
      before do
        allow(machine).to receive(:communicate).and_raise(StandardError.new('Communication error'))
      end

      it 'handles the exception gracefully in ssh_capable?' do
        expect { extractor.ssh_capable? }.not_to raise_error
        expect(extractor.ssh_capable?).to be false
      end
    end
  end
end
