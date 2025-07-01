# Product Requirements Document: Vagrant SSH Config Manager Plugin

## Introduction/Overview

The **Vagrant SSH Config Manager** is a Vagrant plugin that automatically manages SSH configurations by leveraging the same information that is available via Vagrant's built-in `vagrant ssh-config` command output. Unlike vagrant-hostmanager which manages `/etc/hosts` files, this plugin focuses specifically on SSH configuration management, ensuring that `~/.ssh/config` (or a custom SSH config file) is automatically updated when VMs are started and cleaned up when VMs are destroyed.

The plugin solves the problem of manual SSH configuration management for Vagrant environments, automatically incorporating all the SSH connection details that Vagrant already knows (usernames, hostnames, ports, SSH keys, etc.) into the user's SSH configuration, making it seamless to connect to VMs using standard SSH commands.

## Goals

1. **Automate SSH Configuration Management**: Eliminate manual SSH config file updates by automatically adding/removing entries based on VM lifecycle events.
2. **Leverage Vagrant's Native SSH Knowledge**: Access the same SSH connection information that `vagrant ssh-config` provides, but through Vagrant's internal APIs rather than executing external commands.
3. **Ensure Environment Isolation**: Prevent conflicts between different Vagrant projects by using project directory + VM name combinations.
4. **Maintain SSH Config File Integrity**: Provide robust file handling with appropriate locking mechanisms to prevent corruption during concurrent operations.
5. **Offer Flexible Configuration**: Allow users to enable/disable the plugin and specify custom SSH config file locations.

## User Stories

1. **As a DevOps engineer**, I want SSH config entries to be automatically created when I run `vagrant up` so that I can immediately use `ssh <vm-name>` without manual configuration.

2. **As a developer working on multiple projects**, I want SSH entries to be automatically removed when I run `vagrant destroy` so that my SSH config doesn't accumulate stale entries.

3. **As a team member sharing Vagrant configurations**, I want SSH entries to be namespaced by project so that different projects don't interfere with each other's VM names.

4. **As a security-conscious user**, I want to specify a custom SSH config file location so that I can isolate Vagrant-managed entries from my personal SSH configurations.

5. **As a developer working with multi-VM environments**, I want all VMs in my Vagrant environment to have their SSH configurations managed automatically, regardless of how many VMs I start simultaneously.

6. **As a system administrator**, I want the plugin to handle VM state changes (halt, reload, provision) appropriately so that SSH configurations remain accurate after any VM lifecycle event.

## Functional Requirements

1. The plugin **must** automatically execute `vagrant ssh-config` for each VM and parse its output to extract SSH configuration parameters.

2. The plugin **must** add SSH configuration entries to the specified SSH config file when a VM transitions to a running state (via `vagrant up`, `vagrant reload`, `vagrant resume`).

3. The plugin **must** remove corresponding SSH configuration entries when a VM is destroyed (via `vagrant destroy`).

4. The plugin **must** update SSH configuration entries when VM network settings change (via `vagrant reload`, `vagrant provision`).

5. The plugin **must** use a naming scheme that combines the project directory name with the VM name to ensure uniqueness across different Vagrant environments.

6. The plugin **must** implement file locking mechanisms to prevent SSH config file corruption when multiple VMs are started simultaneously.

7. The plugin **must** support configuration via Vagrantfile with at minimum an `enabled` boolean flag and a `ssh_conf_file` path option.

8. The plugin **must** create the specified SSH config file if it doesn't exist, with appropriate file permissions (600).

9. The plugin **must** preserve existing SSH config entries that are not managed by the plugin.

10. The plugin **must** handle VM state changes during `vagrant halt`, `vagrant suspend`, and `vagrant resume` by updating SSH entries as appropriate.

11. The plugin **must** show warnings for SSH config operation failures but continue with VM operations.

12. The plugin **must** add comment markers around managed SSH entries to clearly identify plugin-managed sections.

13. The plugin **must** handle network interface changes and port forwarding updates by refreshing SSH config entries.

14. The plugin **must** support all SSH configuration options that `vagrant ssh-config` provides (Host, HostName, User, Port, UserKnownHostsFile, StrictHostKeyChecking, PasswordAuthentication, IdentityFile, IdentitiesOnly, LogLevel).

15. The plugin **must** create a separate SSH config include file per Vagrant environment/directory and manage the main SSH config file to include it.

16. The plugin **must** silently ignore Vagrant boxes that don't support SSH without blocking other operations.

17. The plugin **must** raise a warning when the SSH config file is write-protected but continue with VM operations.

## Nice to Have Features (Future Enhancements)

1. **Manual Refresh Command**: A command to manually refresh all SSH config entries for an environment (e.g., `vagrant ssh-config-refresh`).
2. **SSH Config File Recovery**: Functionality to handle write-protected SSH config files more gracefully, potentially with user prompts or alternative file locations.

## Non-Goals (Out of Scope)

1. **SSH Key Management**: The plugin will not generate, rotate, or manage SSH keys - it will only reference existing keys as provided by `vagrant ssh-config`.

2. **SSH Config File Backup/Restore**: The plugin will not provide backup or restore functionality for SSH config files.

3. **Multiple SSH Config File Management**: The plugin will only manage one SSH config file at a time per Vagrant environment.

4. **SSH Connection Testing**: The plugin will not test SSH connectivity or validate that SSH configurations work.

5. **Custom SSH Option Templates**: The plugin will not support custom SSH configuration templates beyond what `vagrant ssh-config` provides.

6. **SSH Config File Validation**: The plugin will not validate the syntax or correctness of existing SSH config entries.

7. **Cross-Platform SSH Client Support**: The plugin will focus on standard OpenSSH client configuration format only.

## Design Considerations

- **SSH Config Entry Format**: Entries should be clearly marked with comments indicating they are managed by the plugin, including project path and timestamp.
- **Error Handling**: Operations should be non-blocking - SSH config failures should not prevent VM operations from completing.
- **Logging**: Provide clear logging messages for SSH config operations (add, update, remove) for debugging purposes.
- **Configuration Validation**: Validate Vagrantfile configuration options and provide helpful error messages for invalid settings.

## Technical Considerations

- **Integration Point**: Hook into Vagrant's action middleware system to trigger SSH config updates at appropriate VM lifecycle events.
- **File Locking**: Use Ruby's file locking mechanisms (`File#flock`) to prevent concurrent access issues.
- **SSH Config Include Structure**: Create a dedicated include file per Vagrant environment (e.g., `~/.ssh/config.d/vagrant-project-name`) and manage the main SSH config file to include it.
- **SSH Config Parsing**: Implement robust parsing that can handle various SSH config file formats and preserve existing structure.
- **Cross-Platform Compatibility**: Ensure the plugin works on Windows, macOS, and Linux environments.
- **Vagrant API Usage**: Utilize Vagrant's existing SSH configuration API rather than parsing command output when possible.
- **Performance**: Minimize impact on VM startup time by making SSH config operations as efficient as possible.
- **Error Handling**: Gracefully handle non-SSH-capable boxes and write-protected config files with appropriate warnings.

## Success Metrics

1. **Automatic Entry Management**: SSH config entries are correctly created when VMs start and removed when VMs are destroyed.
2. **No Stale Entries**: No accumulation of outdated or duplicate SSH entries across multiple VM lifecycle operations.
3. **Environment Isolation**: Multiple Vagrant projects can run simultaneously without SSH config conflicts.
4. **File Integrity**: SSH config file remains valid and uncorrupted even with concurrent VM operations.
5. **Configuration Accuracy**: SSH entries contain all necessary connection parameters from `vagrant ssh-config` output.
6. **Non-Interference**: Existing SSH config entries not managed by the plugin remain unchanged.

## Open Questions

~~1. Should the plugin support SSH config file include directives, or only manage entries in the primary config file?~~ **RESOLVED**: Yes, create a separate SSH config include file per Vagrant environment/directory.

~~2. How should the plugin handle Vagrant boxes that don't support SSH (if any)?~~ **RESOLVED**: Silently ignore them.

~~3. Should there be a manual command to refresh all SSH config entries for an environment?~~ **RESOLVED**: Not in initial version, added to "Nice to Have Features" for future enhancement.

~~4. How should the plugin behave when the SSH config file is write-protected?~~ **RESOLVED**: Raise a warning but continue with VM operations.

~~5. Should the plugin provide options to exclude specific VMs from SSH config management?~~ **RESOLVED**: No, not needed.

### Remaining Open Questions

None - all questions have been resolved.
