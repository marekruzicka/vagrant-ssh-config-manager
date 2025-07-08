# Task List: Separate File-Based SSH Configuration Management

Based on the requirement to change the SSH configuration approach from editing the main `~/.ssh/config` file to creating separate files for each VM in a configurable directory with proper Include directive management.

## Relevant Files

- `lib/vagrant-ssh-config-manager/config.rb` - Plugin configuration class that needs new options for directory path and include management.
- `lib/vagrant-ssh-config-manager/ssh_config_manager.rb` - Main SSH config management logic that needs to be updated for separate file approach.
- `lib/vagrant-ssh-config-manager/file_manager.rb` - New class to handle individual SSH config file operations and directory management.
- `lib/vagrant-ssh-config-manager/include_manager.rb` - New class to manage Include directives in the main SSH config file.
- `lib/vagrant-ssh-config-manager/action/up.rb` - Action hook for VM startup that creates individual SSH config files.
- `lib/vagrant-ssh-config-manager/action/destroy.rb` - Action hook for VM destruction that removes individual SSH config files.
- `lib/vagrant-ssh-config-manager/action/reload.rb` - Action hook for VM reload that updates individual SSH config files.
- `lib/vagrant-ssh-config-manager/action/halt.rb` - Action hook for VM halt that may need to handle SSH config state.
- `spec/unit/file_manager_spec.rb` - Unit tests for the new file manager class.
- `spec/unit/include_manager_spec.rb` - Unit tests for the include manager class.
- `spec/unit/config_spec.rb` - Updated unit tests for new configuration options.
- `spec/integration/separate_files_spec.rb` - Integration tests for the separate file approach.

### Notes

- Individual SSH config files will be stored in a configurable directory (default: `~/.ssh/config.d/vagrant/`)
- Each VM will have its own file named using project and VM identifiers
- The main `~/.ssh/config` will include the directory using an Include directive
- File cleanup on destroy is critical to prevent accumulation of stale config files
- Proper file locking mechanisms should be maintained for concurrent operations

## Tasks

- [x] 1.0 Implement Configurable Directory Structure for SSH Config Files
  - [x] 1.1 Add new configuration option `ssh_config_dir` to Config class with default value `~/.ssh/config.d/vagrant/`
  - [x] 1.2 Add configuration validation for directory path format and permissions
  - [x] 1.3 Create directory structure automatically if it doesn't exist with proper permissions (700)
  - [x] 1.4 Add option to disable directory auto-creation for security-conscious users
  - [x] 1.5 Update configuration finalize! method to expand and validate directory paths
  - [x] 1.6 Add configuration option to control Include directive management (`manage_includes` boolean)

- [x] 2.0 Create Individual VM SSH Configuration Files
  - [x] 2.1 Create new FileManager class to handle individual SSH config file operations
  - [x] 2.2 Implement file naming strategy: `{project_hash}-{vm_name}.conf` to ensure uniqueness
  - [x] 2.3 Generate individual SSH config file content with proper SSH config format
  - [x] 2.4 Add comment headers to files indicating they are managed by vagrant-ssh-config-manager
  - [x] 2.5 Implement atomic file writing with temporary files and rename operations
  - [x] 2.6 Add file permission management (600) for individual config files
  - [x] 2.7 Handle file locking for concurrent VM operations in the same project
  - [x] 2.8 Implement file content validation before writing

- [x] 3.0 Manage SSH Config Include Directives
  - [x] 3.1 Create new IncludeManager class to handle Include directive operations
  - [x] 3.2 Check if main SSH config file contains Include directive for the config directory
  - [x] 3.3 Add Include directive to main SSH config file if not present and `manage_includes` is enabled
  - [x] 3.4 Parse existing SSH config to find optimal location for Include directive (beginning of file)
  - [x] 3.5 Implement backup mechanism before modifying main SSH config file
  - [x] 3.6 Add plugin identification comments around managed Include directives
  - [x] 3.7 Remove Include directive when no more VM config files exist and cleanup is enabled
  - [x] 3.8 Handle edge cases: empty main config file, write-protected main config, malformed config

- [x] 4.0 Implement File Cleanup on VM Destruction
  - [x] 4.1 Update destroy action to remove individual SSH config files for destroyed VMs
  - [x] 4.2 Implement safe file removal with existence checks and error handling
  - [x] 4.3 Add directory cleanup when it becomes empty (configurable behavior)
  - [x] 4.4 Remove Include directive from main config when directory becomes empty
  - [x] 4.5 Add logging for file removal operations with success/failure indication
  - [x] 4.6 Handle partial cleanup failures gracefully without blocking VM destruction
  - [x] 4.7 Add cleanup verification to ensure files are actually removed
  - [x] 4.8 Implement orphaned file detection and cleanup for abandoned configurations

- [x] 5.0 Update Plugin Configuration Options and Validation
  - [x] 5.1 Update Config class with new configuration attributes for separate file approach
  - [x] 5.2 Add backward compatibility for existing `ssh_conf_file` option (legacy support)
  - [x] 5.3 Implement configuration migration logic from old to new approach
  - [x] 5.4 Add comprehensive validation for directory paths, permissions, and include options
  - [x] 5.5 Update configuration documentation and examples in README
  - [x] 5.6 Add configuration option to choose between legacy and new approaches
  - [x] 5.7 Implement configuration conflict detection (legacy vs new options)
  - [x] 5.8 Add deprecation warnings for legacy configuration options
