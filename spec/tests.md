# Test Suite Overview

This document provides a summary of all test cases in the `spec/` directory for the `vagrant-ssh-config-manager` plugin.

---

## spec/spec_helper.rb

- **Purpose**: Configures RSpec environment and shared helpers.
- **Key points**:
  - Sets up temporary HOME directory and `~/.ssh/config.d` for each example.
  - Provides helper methods:
    - `read_ssh_config`: reads the main SSH config or returns empty string.
    - `include_files`: lists files in `config.d` matching `vagrant-*` (aliased as `get_include_files`).
  - Mocks `Log4r::Logger` to no-op logging.

---

## spec/unit/file_manager_spec.rb

Tests for `VagrantPlugins::SshConfigManager::FileManager`:

1. **Initialization**
   - Verifies `FileManager.new(config)` returns an instance.

2. **`#generate_filename`**
   - Generates a filename matching `/^[a-f0-9]{8}-<vm>.conf$/`.
   - Consistent output for same inputs.
   - Different project paths yield different hashes.

3. **`#get_file_path`**
   - Ensures full path is under `ssh_config_dir` and ends with `.conf`.

4. **`#generate_ssh_config_content`**
   - Returns `nil` when `ssh_info` is not available.
   - Produces valid SSH config string when `ssh_info` is provided.

5. **`#write_ssh_config_file`**
   - Writes file atomically under `ssh_config_dir`.
   - Creates directory if missing.
   - Sets file permissions to `0o600`.

6. **`#remove_ssh_config_file`**
   - Deletes the file when it exists.
   - Returns `false` when file is absent.
   - Optionally cleans up empty directory when `cleanup_empty_dir` is enabled.

7. **`#ssh_config_file_exists?`**
   - Checks existence of the SSH config file.

8. **`#validate_ssh_config_content`**
   - Validates strings containing `Host`, `HostName`, and `Port`.
   - Rejects `nil`, empty, or invalid content.

9. **`#cleanup_orphaned_files`**
   - Removes `.conf` files not matching the active machines list.
   - Returns count of removed files.

10. **Backward compatibility**
    - Aliases `get_file_path` and `get_all_config_files`.

---

## spec/unit/ssh_config_manager_spec.rb

Tests for `VagrantPlugins::SshConfigManager::SshConfigManager`:

1. **Project Isolation**
   - Ensures `generate_project_identifier` produces stable IDs per project path.

2. **Include File Operations**
   - Adds include directives to main SSH config.
   - Writes entries with proper comment blocks.
   - Removes entries and include directives on cleanup.

3. **Section Markers**
   - Verifies `format_comment_block` and marker insertion/removal logic.

4. **Migration & Cleanup**
   - Tests `migrate_to_project_naming?`, `cleanup_comment_markers?`, and related aliases.

5. **Statistics & Hosts**
   - `project_hosts`, `project_stats`, and backward-compatible aliases.

---

**Note**: For any new features or refactors, please add corresponding test cases in this directory.
