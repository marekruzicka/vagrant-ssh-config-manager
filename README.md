# Vagrant SSH Config Manager

A Vagrant plugin that automatically manages SSH configuration entries for Vagrant-managed VMs, providing seamless SSH access without the need to remember ports, IPs, or key locations.

## Features

- **Automatic SSH Config Management**: Creates and maintains SSH config files when VMs are started
- **Project Isolation**: Each Vagrant project gets its own SSH config namespace to avoid conflicts
- **Separate File Management**: Creates individual SSH config files for each VM in a dedicated directory
- **Include Directive Management**: Automatically manages Include directives in your main SSH config
- **Lifecycle Integration**: Hooks into all Vagrant VM lifecycle events (up, destroy, reload, halt, provision)
- **Configurable Behavior**: Extensive configuration options for different workflows
- **Robust Error Handling**: Graceful handling of file permission issues and concurrent access
- **File Locking**: Prevents SSH config corruption during concurrent operations
- **Backup Support**: Creates backups before modifying SSH config files

## Installation

### Install from RubyGems (Recommended)

```bash
vagrant plugin install vagrant-ssh-config-manager
```

### Install from Source

```bash
git clone https://github.com/your-username/vagrant-ssh-config-manager.git
cd vagrant-ssh-config-manager
gem build vagrant-ssh-config-manager.gemspec
vagrant plugin install vagrant-ssh-config-manager-*.gem
```

## Quick Start

1. Install the plugin
2. Add configuration to your `Vagrantfile` (optional)
3. Run `vagrant up`
4. Connect to your VM with: `ssh <project>-<machine-name>`

### Example

```ruby
# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  
  # Optional: Configure the plugin (uses sensible defaults)
  config.sshconfigmanager.enabled = true
  config.sshconfigmanager.ssh_config_dir = "~/.ssh/config.d/vagrant"
  config.sshconfigmanager.manage_includes = true
  
  config.vm.define "web" do |web|
    web.vm.network "private_network", ip: "192.168.33.10"
  end
end
```

After `vagrant up`, you can connect with:
```bash
ssh vagrant-web  # Project + machine name
```

## Configuration

All configuration options are available in your `Vagrantfile`:

```ruby
Vagrant.configure("2") do |config|
  config.sshconfigmanager.enabled = true                        # Enable/disable plugin (default: true)
  config.sshconfigmanager.ssh_config_dir = "~/.ssh/config.d/vagrant" # Directory for individual SSH config files (default)
  config.sshconfigmanager.manage_includes = false               # Manage Include directive in main SSH config (default: false)
  config.sshconfigmanager.auto_create_dir = true                # Auto-create SSH config dir if missing (default: true)
  config.sshconfigmanager.cleanup_empty_dir = true              # Remove empty SSH config dir when no VMs remain (default: true)
  config.sshconfigmanager.auto_remove_on_destroy = true         # Remove SSH entries on VM destroy (default: true)
  config.sshconfigmanager.update_on_reload = true               # Update SSH entries on VM reload (default: true)
  config.sshconfigmanager.refresh_on_provision = true           # Refresh SSH entries on VM provision (default: true)
  config.sshconfigmanager.keep_config_on_halt = true            # Keep SSH entries when VM is halted (default: true)
  config.sshconfigmanager.project_isolation = true              # Use project-specific naming (default: true)
end
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | Boolean | `true` | Enable or disable the plugin globally |
| `ssh_config_dir` | String | `~/.ssh/config.d/vagrant` | Directory for individual SSH config files |
| `manage_includes` | Boolean | `false` | Automatically manage Include directive in main SSH config |
| `auto_create_dir` | Boolean | `true` | Automatically create SSH config directory if it doesn't exist |
| `cleanup_empty_dir` | Boolean | `true` | Remove empty SSH config directory when no VMs remain |
| `auto_remove_on_destroy` | Boolean | `true` | Remove SSH entries when VM is destroyed |
| `update_on_reload` | Boolean | `true` | Update SSH entries when VM is reloaded |
| `refresh_on_provision` | Boolean | `true` | Refresh SSH entries when VM is provisioned |
| `keep_config_on_halt` | Boolean | `true` | Keep SSH entries when VM is halted/suspended |
| `project_isolation` | Boolean | `true` | Use project-specific naming for SSH entries.<br>Set to `false` if using together with `vagrant-hostmanager`.<br>**Be mindful of hostname collisions!** |

## How It Works

### Separate File Architecture (Default)

The plugin creates individual SSH config files for each VM in a dedicated directory (default: `~/.ssh/config.d/vagrant/`). This approach:

- **Prevents conflicts**: Each VM has its own config file
- **Enables easier cleanup**: Destroying a VM removes only its config file
- **Supports concurrent operations**: Multiple VMs can be managed simultaneously
- **Maintains cleaner config**: Main SSH config stays uncluttered

### SSH Config Structure

```
~/.ssh/config                           # Your main SSH config
~/.ssh/config.d/vagrant/                # Plugin-managed directory
  ├── a1b2c3d4-web.conf                # Individual VM config files
  ├── a1b2c3d4-db.conf
  └── f5e6d7c8-api.conf                # From different projects
```

### Include Directive Management

When `manage_includes` is enabled (default: false), the plugin automatically adds:

```
# ~/.ssh/config
# BEGIN vagrant-ssh-config-manager
Include ~/.ssh/config.d/vagrant/*.conf
# END vagrant-ssh-config-manager

# Your existing SSH configuration continues here...
```

### Project Isolation

Each Vagrant project gets a unique identifier based on the project path:
- Project path: `/home/user/my-app`
- Project hash: `a1b2c3d4` (first 8 chars of MD5)
- SSH host names: `my-app-web`, `my-app-db`
- Config files: `a1b2c3d4-web.conf`, `a1b2c3d4-db.conf`

### Individual Config File Example

```
# ~/.ssh/config.d/vagrant/a1b2c3d4-web.conf
# Managed by vagrant-ssh-config-manager plugin
# Project: my-app
# VM: web
# Generated: 2025-01-01 12:00:00

Host my-app-web
  HostName 192.168.33.10
  Port 22
  User vagrant
  IdentityFile /home/user/.vagrant.d/insecure_private_key
  IdentitiesOnly yes
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  LogLevel FATAL
```

### Main SSH Config Integration

When `manage_includes` is enabled, the plugin automatically adds an Include directive:

```
# ~/.ssh/config
# BEGIN vagrant-ssh-config-manager
Include ~/.ssh/config.d/vagrant/*.conf
# END vagrant-ssh-config-manager

# Your existing SSH configuration...
```

## Usage Examples

### Basic Multi-Machine Setup

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "generic/debian12"
  
  config.vm.define "web" do |web|
    web.vm.network "private_network", ip: "192.168.33.10"
  end
  
  config.vm.define "db" do |db|
    db.vm.network "private_network", ip: "192.168.33.11"
  end
end
```

Connect to machines:
```bash
vagrant up
ssh vagrant-web
ssh vagrant-db
```

### Disable for Specific Environments

```ruby
Vagrant.configure("2") do |config|
  # Disable in production environment
  config.sshconfigmanager.enabled = ENV['VAGRANT_ENV'] != 'production'
  # ... rest of config
end
```

## Troubleshooting

### Common Issues

#### Permission Denied
```
SSH config manager: Permission denied. Check file permissions.
```
**Solution**: Ensure SSH config file and directory are writable:
```bash
chmod 600 ~/.ssh/config
chmod 700 ~/.ssh
```

#### File Not Found
```
SSH config manager: SSH config file cannot be created
```
**Solution**: Ensure SSH directory exists:
```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

#### Concurrent Access Issues
The plugin uses separate ssh config file for each of the servers... there should be no concurrency issues by design.  


### Debugging

Enable Vagrant debug output:
```bash
VAGRANT_LOG=debug vagrant up
```

Check plugin logs in the output for SSH config manager operations.

### Manual Cleanup

If you need to manually clean up SSH config entries:

```bash
# Remove all Vagrant-managed entries
rm ~/.ssh/config.d/vagrant/*

# Remove include directive from main config
sed -i '/# BEGIN vagrant-ssh-config-manager/,/# END vagrant-ssh-config-manager/d' ~/.ssh/config
```

## Compatibility

- **Vagrant**: 2.0+
- **Ruby**: 3.0+
- **Platforms**: Linux, macOS, Windows (with WSL)
- **Providers**: VirtualBox, VMware, Libvirt, Hyper-V, Docker, AWS, and others

## License

MIT License - see [LICENSE](LICENSE) file for details.
