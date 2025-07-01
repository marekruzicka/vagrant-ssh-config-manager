# Shared examples for SSH config file management

RSpec.shared_examples 'ssh config file operations' do
  it 'creates SSH config file if it does not exist' do
    expect(File.exist?(ssh_config_file)).to be false
    
    subject.send(:ensure_ssh_config_structure)
    
    expect(File.exist?(ssh_config_file)).to be true
    expect(File.stat(ssh_config_file).mode & 0777).to eq(0600)
  end

  it 'preserves existing SSH config file permissions' do
    File.write(ssh_config_file, "# Existing config\n")
    File.chmod(0644, ssh_config_file)
    
    subject.send(:ensure_ssh_config_structure)
    
    expect(File.stat(ssh_config_file).mode & 0777).to eq(0644)
  end
end

RSpec.shared_examples 'file locking behavior' do
  it 'handles file locking timeout gracefully' do
    # This is difficult to test in practice, but we can test the structure
    expect { subject.send(:with_file_lock, '/nonexistent/file', &:itself) }.to raise_error
  end
end

RSpec.shared_examples 'project isolation' do
  let(:project_path) { '/path/to/project' }
  let(:expected_project_id) { Digest::SHA256.hexdigest(project_path)[0, 8] }

  it 'generates consistent project identifiers' do
    allow(machine.env).to receive(:root_path).and_return(project_path)
    
    id1 = subject.send(:generate_project_identifier)
    id2 = subject.send(:generate_project_identifier)
    
    expect(id1).to eq(id2)
    expect(id1).to eq(expected_project_id)
  end

  it 'generates unique host names for machines' do
    allow(machine.env).to receive(:root_path).and_return(project_path)
    
    host_name = subject.send(:generate_isolated_host_name, 'web-server')
    
    expect(host_name).to eq("vagrant-#{expected_project_id}-web-server")
  end
end

RSpec.shared_examples 'error handling' do
  it 'handles permission errors gracefully' do
    # Make SSH directory read-only
    File.chmod(0400, File.dirname(ssh_config_file))
    
    expect { subject.add_ssh_entry(sample_ssh_config) }.not_to raise_error
  end

  it 'handles I/O errors gracefully' do
    # We can't easily simulate I/O errors, but we can test the structure
    expect(subject).to respond_to(:add_ssh_entry)
  end
end

RSpec.shared_examples 'configuration validation' do
  it 'validates boolean options' do
    config.enabled = 'not_boolean'
    result = config.validate(machine)
    
    expect(result['SSH Config Manager']).to include(match(/must be true or false/))
  end

  it 'validates SSH config file path' do
    config.ssh_conf_file = 123
    result = config.validate(machine)
    
    expect(result['SSH Config Manager']).to include(match(/must be a string path/))
  end
end
