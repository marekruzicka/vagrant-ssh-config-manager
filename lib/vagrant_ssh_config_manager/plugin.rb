# frozen_string_literal: true

require 'vagrant'

module VagrantPlugins
  module SshConfigManager
    class Plugin < Vagrant.plugin('2')
      name 'SSH Config Manager'
      description <<-DESC
      This plugin automatically manages SSH configurations by leveraging Vagrant's#{' '}
      internal SSH knowledge. It creates and maintains SSH config entries when VMs#{' '}
      are started and cleans them up when VMs are destroyed.
      DESC

      # Register the configuration class
      config :sshconfigmanager do
        require 'vagrant_ssh_config_manager/config'
        Config
      end

      # Hook into various Vagrant actions
      action_hook(:ssh_config_manager, :machine_action_up) do |hook|
        require 'vagrant_ssh_config_manager/action/up'
        hook.after(Vagrant::Action::Builtin::WaitForCommunicator, Action::Up)
      end

      action_hook(:ssh_config_manager, :machine_action_destroy) do |hook|
        require 'vagrant_ssh_config_manager/action/destroy'
        hook.before(Vagrant::Action::Builtin::DestroyConfirm, Action::Destroy)
      end

      action_hook(:ssh_config_manager, :machine_action_reload) do |hook|
        require 'vagrant_ssh_config_manager/action/reload'
        hook.after(Vagrant::Action::Builtin::WaitForCommunicator, Action::Reload)
      end

      action_hook(:ssh_config_manager, :machine_action_halt) do |hook|
        require 'vagrant_ssh_config_manager/action/halt'
        hook.before(Vagrant::Action::Builtin::GracefulHalt, Action::Halt)
      end

      action_hook(:ssh_config_manager, :machine_action_suspend) do |hook|
        require 'vagrant_ssh_config_manager/action/halt'
        hook.before(Vagrant::Action::Builtin::Suspend, Action::Halt)
      end

      action_hook(:ssh_config_manager, :machine_action_resume) do |hook|
        require 'vagrant_ssh_config_manager/action/up'
        hook.after(Vagrant::Action::Builtin::Resume, Action::Up)
      end

      action_hook(:ssh_config_manager, :machine_action_provision) do |hook|
        require 'vagrant_ssh_config_manager/action/provision'
        hook.after(Vagrant::Action::Builtin::Provision, Action::Provision)
      end
    end
  end
end
