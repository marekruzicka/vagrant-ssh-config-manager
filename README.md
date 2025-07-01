# Vagrant SSH Config Manager

A Vagrant plugin that automatically manages SSH configuration entries for Vagrant-managed VMs, providing seamless SSH access without the need to remember ports, IPs, or key locations.

## Features

- **Automatic SSH Config Management**: Creates and maintains SSH config entries when VMs are started
- **Project Isolation**: Each Vagrant project gets its own SSH config namespace to avoid conflicts
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
bundle install
bundle exec rake build
vagrant plugin install pkg/vagrant-ssh-config-manager-*.gem
```

## Quick Start

1. Install the plugin
2. Add configuration to your `Vagrantfile` (optional)
3. Run `vagrant up`
4. Connect to your VM with: `ssh vagrant-<project>-<machine-name>`

### Example

```ruby
# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  
  # Optional: Configure the plugin
  config.sshconfigmanager.enabled = true
  config.sshconfigmanager.ssh_conf_file = "~/.ssh/config"
  
  config.vm.define "web" do |web|
    web.vm.network "private_network", ip: "192.168.33.10"
  end
end
```

After `vagrant up`, you can connect with:
```bash
ssh vagrant-a1b2c3d4-web  # Project hash + machine name
```

## Configuration

All configuration options are available in your `Vagrantfile`:

```ruby
Vagrant.configure("2") do |config|
  config.sshconfigmanager.enabled = true                    # Enable/disable plugin (default: true)
  config.sshconfigmanager.ssh_conf_file = "~/.ssh/config"   # SSH config file path (default: ~/.ssh/config)
  config.sshconfigmanager.auto_remove_on_destroy = true     # Remove entries on destroy (default: true)
  config.sshconfigmanager.update_on_reload = true           # Update entries on reload (default: true)
  config.sshconfigmanager.refresh_on_provision = true       # Refresh entries on provision (default: true)
  config.sshconfigmanager.keep_config_on_halt = true        # Keep entries when halted (default: true)
  config.sshconfigmanager.project_isolation = true          # Use project-based naming (default: true)
end
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | Boolean | `true` | Enable or disable the plugin globally |
| `ssh_conf_file` | String | `~/.ssh/config` | Path to SSH config file to manage |
| `auto_remove_on_destroy` | Boolean | `true` | Remove SSH entries when VM is destroyed |
| `update_on_reload` | Boolean | `true` | Update SSH entries when VM is reloaded |
| `refresh_on_provision` | Boolean | `true` | Refresh SSH entries when VM is provisioned |
| `keep_config_on_halt` | Boolean | `true` | Keep SSH entries when VM is halted/suspended |
| `project_isolation` | Boolean | `true` | Use project-specific naming for SSH entries |

## How It Works

### SSH Config Structure

The plugin creates a clean separation between your existing SSH config and Vagrant-managed entries:

```
~/.ssh/config                    # Your main SSH config
~/.ssh/config.d/                 # Directory for include files
  └── vagrant-a1b2c3d4           # Project-specific include file
```

### Project Isolation

Each Vagrant project gets a unique identifier based on the project path:
- Project path: `/home/user/my-app`
- Project hash: `a1b2c3d4` (first 8 chars of SHA256)
- SSH host names: `vagrant-a1b2c3d4-web`, `vagrant-a1b2c3d4-db`

### Include File Example

```
# ~/.ssh/config.d/vagrant-a1b2c3d4
# Vagrant SSH Config - Project: my-app
# Generated on: 2025-01-01 12:00:00
# DO NOT EDIT MANUALLY - Managed by vagrant-ssh-config-manager

Host vagrant-a1b2c3d4-web
  HostName 192.168.33.10
  Port 22
  User vagrant
  IdentityFile /home/user/.vagrant.d/insecure_private_key
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel QUIET
```

### Main SSH Config Integration

```
# ~/.ssh/config
# Your existing SSH configuration...

# === Vagrant SSH Config Manager ===
Include ~/.ssh/config.d/vagrant-*
# === End Vagrant SSH Config Manager ===
```

## Usage Examples

### Basic Multi-Machine Setup

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  
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
ssh vagrant-a1b2c3d4-web
ssh vagrant-a1b2c3d4-db
```

### Custom SSH Config Location

```ruby
Vagrant.configure("2") do |config|
  config.sshconfigmanager.ssh_conf_file = "~/.ssh/vagrant_config"
  # ... rest of config
end
```

### Disable for Specific Environments

```ruby
Vagrant.configure("2") do |config|
  # Disable in production environment
  config.sshconfigmanager.enabled = ENV['VAGRANT_ENV'] != 'production'
  # ... rest of config
end
```

### Custom Naming Strategy

While the plugin uses project isolation by default, you can work with the generated names:

```bash
# Find your project's SSH entries
grep -n "Host vagrant-" ~/.ssh/config.d/vagrant-*

# Or list all Vagrant-managed entries
ssh -F ~/.ssh/config vagrant-<TAB><TAB>  # If your shell supports completion
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
The plugin uses file locking to prevent corruption, but if you see timeout errors:
```bash
# Check for processes holding locks
lsof ~/.ssh/config
```

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
rm ~/.ssh/config.d/vagrant-*

# Remove include directive from main config
sed -i '/# === Vagrant SSH Config Manager ===/,/# === End Vagrant SSH Config Manager ===/d' ~/.ssh/config
```

## Development

### Running Tests

```bash
bundle install
bundle exec rspec
```

### Code Structure

```
lib/
├── vagrant-ssh-config-manager.rb           # Main entry point
└── vagrant-ssh-config-manager/
    ├── plugin.rb                          # Plugin registration
    ├── config.rb                          # Configuration class
    ├── ssh_info_extractor.rb              # SSH info extraction
    ├── ssh_config_manager.rb              # Core SSH config management
    ├── file_locker.rb                     # File locking mechanism
    ├── version.rb                         # Version constant
    └── action/                            # Vagrant action hooks
        ├── up.rb
        ├── destroy.rb
        ├── reload.rb
        ├── halt.rb
        └── provision.rb
```

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for your changes
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Create a Pull Request

## Compatibility

- **Vagrant**: 2.0+
- **Ruby**: 2.4+
- **Platforms**: Linux, macOS, Windows (with WSL)
- **Providers**: VirtualBox, VMware, Libvirt, Hyper-V, Docker, AWS, and others

## Similar Projects

- [vagrant-hostmanager](https://github.com/devopsgroup-io/vagrant-hostmanager) - Manages `/etc/hosts` entries
- [vagrant-ssh-config](https://github.com/glenndehaan/vagrant-ssh-config) - Basic SSH config generation

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Changelog

### v1.0.0 (2025-01-01)
- Initial release
- Automatic SSH config management
- Project isolation
- Full Vagrant lifecycle integration
- Comprehensive configuration options
- File locking and error handling
- Extensive test coverage

## Support

- **Issues**: [GitHub Issues](https://github.com/your-username/vagrant-ssh-config-manager/issues)
- **Documentation**: This README and inline code documentation
- **Community**: Discussions tab on GitHub repository

---

**Made with ❤️ for the Vagrant community**
