# Development Guide

This document provides information for developers working on the vagrant-ssh-config-manager plugin.

## Prerequisites

- Ruby 2.6 or higher
- Bundler 2.0 or higher
- Git
- Vagrant 2.0 or higher (for testing)

## Development Setup

### Clone and Setup

```bash
git clone https://github.com/your-username/vagrant-ssh-config-manager.git
cd vagrant-ssh-config-manager
bundle install --without plugins  # Install dev dependencies without Vagrant
```

### Project Structure

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
spec/
├── spec_helper.rb                         # RSpec configuration
├── unit/                                  # Unit tests
│   ├── config_spec.rb
│   ├── file_locker_spec.rb
│   ├── ssh_config_manager_spec.rb
│   └── ssh_info_extractor_spec.rb
├── integration/                           # Integration tests
│   └── plugin_integration_spec.rb
└── support/                               # Test support files
    └── shared_examples.rb
```

## Building the Gem

### Quick Build (without dependencies)

To build the gem without installing any runtime dependencies (including Vagrant and gRPC):

```bash
gem build vagrant-ssh-config-manager.gemspec
```

This creates `vagrant-ssh-config-manager-x.x.x.gem` in the current directory.

### Development Build with Testing

For development work where you need to run tests:

```bash
# Install dependencies excluding Vagrant (which pulls in gRPC)
bundle install --without development test

# Run tests
bundle exec rspec

# Build gem
bundle exec rake build
```

### Full Build (no longer needed)

The project has been simplified to remove Vagrant dependencies from testing. All tests now run without requiring Vagrant to be installed.

## Testing

### Running Tests

```bash
# Run all unit tests (fast, no Vagrant required)
bundle exec rspec

# Run with coverage report
bundle exec rspec --format documentation
```

### Test Structure

- **Unit tests**: Test individual classes and methods in isolation
- **Core functionality**: Tests focus on file operations, locking, and configuration without heavy Vagrant mocking

### Adding Tests

When adding new functionality:

1. Write unit tests for new classes/methods that don't depend on Vagrant APIs
2. Focus on testing core logic like file operations, string processing, and error handling
3. Ensure both success and failure paths are covered
4. Avoid complex Vagrant API mocking

## Code Quality

### Linting

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues where possible
bundle exec rubocop -a
```

### Coverage

Coverage reports are generated when running RSpec with SimpleCov:

```bash
bundle exec rspec
open coverage/index.html  # View coverage report
```

## Dependency Management

### Gemfile Groups

- `:development, :test` - Development and testing tools (RSpec, RuboCop, SimpleCov)
- `:plugins` - Contains Vagrant for integration testing only

### Installing Without Heavy Dependencies

```bash
# For building only (no Vagrant/gRPC)
bundle install --without development test

# For development (no Vagrant/gRPC)
bundle install --without development test

# Note: The project has been simplified to not require Vagrant for basic development
```

### Why Vagrant Dependency Was Removed

The `spec.add_dependency "vagrant"` was removed from the gemspec because:

1. Vagrant plugins run within Vagrant's runtime environment
2. The dependency created circular issues during installation
3. Users must have Vagrant installed to use `vagrant plugin install`
4. Removing it eliminates the gRPC dependency chain for gem building

## Release Process

### Version Bumping

1. Update version in `lib/vagrant-ssh-config-manager/version.rb`
2. Update CHANGELOG.md with new version and changes
3. Commit version changes

### Building Release

```bash
# Clean build without dependencies
gem build vagrant-ssh-config-manager.gemspec

# Verify gem contents
gem contents pkg/vagrant-ssh-config-manager-x.x.x.gem
```

### Testing Release Locally

```bash
# Install locally built gem
vagrant plugin install pkg/vagrant-ssh-config-manager-x.x.x.gem

# Test in a sample Vagrant project
cd /path/to/test/vagrant/project
vagrant up

# Uninstall when done testing
vagrant plugin uninstall vagrant-ssh-config-manager
```

## Debugging

### Plugin Development

```bash
# Enable Vagrant debug logging
VAGRANT_LOG=debug vagrant up

# Check plugin loading
vagrant plugin list
```

### Common Issues

#### Plugin Not Loading
- Check `lib/vagrant-ssh-config-manager.rb` requires the plugin correctly
- Verify plugin metadata in gemspec: `spec.metadata["vagrant_plugin"] = "true"`
- Ensure plugin registration in `lib/vagrant-ssh-config-manager/plugin.rb`

#### Bundler/Dependency Issues
- Use `bundle exec` for all commands when in development
- Check `.bundle/config` for persistent Bundler settings
- Clear bundle cache: `bundle exec bundle clean --force`

#### Test Failures
- Ensure test isolation - tests should not depend on external state
- Check file permissions in test scenarios
- Verify mock/stub setup in failing tests

## Code Style Guidelines

### Ruby Style

- Follow RuboCop configuration in `.rubocop.yml`
- Use descriptive method and variable names
- Keep methods small and focused
- Prefer explicit returns in public methods

### Error Handling

- Use specific exception classes
- Provide helpful error messages
- Log important operations for debugging
- Handle file I/O failures gracefully

### Documentation

- Document public APIs with YARD-style comments
- Keep README user-focused
- Update this development guide when changing build/test processes
- Comment non-obvious logic in code

## Contributing

### Before Submitting PRs

1. Run full test suite: `bundle exec rspec`
2. Check code style: `bundle exec rubocop`
3. Verify gem builds: `gem build vagrant-ssh-config-manager.gemspec`
4. Test with a real Vagrant project
5. Update documentation if needed

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type(scope): description

feat(ssh): add support for custom SSH config templates
fix(locking): resolve race condition in file locking
docs(readme): update installation instructions
test(unit): add tests for SSH info extraction
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes following the style guidelines
4. Add/update tests for your changes
5. Update documentation if needed
6. Ensure all checks pass
7. Submit PR with clear description of changes

## Architecture Notes

### Plugin Lifecycle

The plugin hooks into Vagrant's action system:

1. **Up**: Extract SSH info, create/update config entries
2. **Reload**: Update existing config entries with new SSH info
3. **Provision**: Optionally refresh config entries
4. **Halt**: Optionally keep or remove config entries
5. **Destroy**: Remove config entries and clean up

### File Locking Strategy

- Uses `flock` for cross-process synchronization
- Timeout-based to prevent indefinite blocking
- Graceful fallback when locking fails

### Configuration Management

- Plugin config is validated at Vagrant config load time
- Default values are applied during validation
- Config errors are reported early in Vagrant lifecycle

## Troubleshooting Development Issues

### Gem Build Fails

```bash
# Check gemspec syntax
ruby vagrant-ssh-config-manager.gemspec

# Verify file patterns match expected files
git ls-files | grep -E '^lib/'
```

### Tests Fail in CI but Pass Locally

- Check Ruby version compatibility
- Verify all dependencies are properly specified
- Look for environment-specific assumptions in tests

### Vagrant Plugin Installation Fails

- Ensure gemspec has `spec.metadata["vagrant_plugin"] = "true"`
- Check that main plugin file properly registers with Vagrant
- Verify no syntax errors in plugin code

---

For questions about development, please open an issue or discussion on GitHub.
