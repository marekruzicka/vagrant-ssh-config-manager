# Hybrid Testing for vagrant-ssh-config-manager

This project uses a **hybrid testing approach** that combines fast unit tests with comprehensive integration tests.

## 🚀 Quick Start

```bash
# Run unit tests (fast, recommended for development)
bundle exec rspec spec/unit/

# Run integration tests (real APIs)
./test-integration.sh

# Run both test suites
./test-hybrid.sh

# Helper scripts for detailed output:
./test-unit.sh           # Unit tests with documentation format
./test-integration.sh    # Integration tests with documentation format
./test-hybrid.sh         # Both suites with progress format
```

## 📁 Test Structure

```
spec/
├── unit_helper.rb           # Minimal setup for unit tests
├── integration_helper.rb    # Real Vagrant setup for integration tests
├── unit/                    # Fast, isolated unit tests
│   ├── config_spec.rb      # ✅ Config class (32 examples)
│   └── file_locker_spec.rb # ✅ FileLocker class (27 examples)
├── integration/             # Real API integration tests
│   └── include_manager_spec.rb # ✅ IncludeManager (14 examples)
└── legacy/                  # Moved legacy test files (not run)
```

## ✅ Current Test Status

- **Unit Tests**: 59 examples, 0 failures (0.07s)
- **Integration Tests**: 14 examples, 0 failures (0.02s)
- **Total Working**: 73 examples, 0 failures

## 🔧 Test Types

### Unit Tests (spec/unit/)
- **Purpose**: Fast feedback, isolated component testing
- **Setup**: Mocked dependencies, no real Vagrant loading
- **Speed**: ~0.07 seconds for 59 tests
- **Coverage**: Config validation, FileLocker concurrency

### Integration Tests (spec/integration/)
- **Purpose**: Real API verification, end-to-end testing
- **Setup**: Real Vagrant APIs, isolated file system environments
- **Speed**: ~0.02 seconds for 14 tests
- **Coverage**: SSH config manipulation, plugin markers

## 🛠 Helper Scripts

- `./test-unit.sh` - Run only unit tests with detailed output
- `./test-integration.sh` - Run only integration tests with detailed output  
- `./test-hybrid.sh` - Run both test suites with summary

## 🧹 Legacy Cleanup

Legacy test files with conflicts have been moved to `spec/legacy/` and are not executed:
- `file_manager_spec.rb`
- `include_manager_spec.rb` (replaced by integration version)
- `ssh_config_manager_enhanced_spec.rb`
- `ssh_config_manager_spec.rb`
- Various backup files

## 📊 Benefits

- **Fast Development**: Unit tests provide immediate feedback
- **Confidence**: Integration tests verify real API behavior
- **Clean Separation**: No conflicts between mocked and real dependencies
- **Maintainable**: Clear structure for future development
