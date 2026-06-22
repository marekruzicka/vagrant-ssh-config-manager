# frozen_string_literal: true

RSpec.describe 'plugin action hooks' do
  let(:plugin_source) do
    File.read(File.expand_path('../../lib/vagrant_ssh_config_manager/plugin.rb', __dir__))
  end

  it 'does not reference nonexistent suspend or resume built-in action constants' do
    expect(plugin_source).not_to include('Vagrant::Action::Builtin::Suspend')
    expect(plugin_source).not_to include('Vagrant::Action::Builtin::Resume')
  end
end
