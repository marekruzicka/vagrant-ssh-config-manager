# Hybrid Testing for vagrant-ssh-config-manager

This project uses a **hybrid testing approach** that combines fast unit tests with comprehensive integration tests.

## 🚀 Quick Start

```bash
# Run unit tests (fast, recommended for development)
bundle exec rspec spec/unit/

# Run integration tests (real APIs)
bundle exec rspec spec/integration/

# Run both test suites
./test-all.sh

# Helper scripts for detailed output:
./test-unit.sh           # Unit tests with documentation format
./test-integration.sh    # Integration tests with documentation format
./test-all.sh            # Both suites with progress format
```

## 📁 Test Structure

```
spec/
├── unit_helper.rb           # Minimal setup for unit tests
├── integration_helper.rb    # Real Vagrant setup for integration tests
├── unit/                    # Fast, isolated unit tests
│   ├── config_spec.rb          # ✅ Config class (32 examples)
│   ├── file_locker_spec.rb     # ✅ FileLocker class (27 examples)
│   ├── file_manager_spec.rb    # ✅ FileManager class (39 examples)
│   └── ssh_config_manager_spec.rb # ✅ SshConfigManager class (43 examples)
└── integration/             # Real API integration tests
    └── include_manager_spec.rb # ✅ IncludeManager (14 examples)
```

## ✅ Current Test Status

- **Unit Tests**: 141 examples, 0 failures (~0.23s)
- **Integration Tests**: 14 examples, 0 failures (~0.02s)
- **Total**: **155 examples, 0 failures** (100% pass rate)
- **Combined Runtime**: ~0.25 seconds (extremely fast!)

## 🚀 Performance Metrics

```bash
$ ./test-all.sh
📦 Unit Tests: 141 examples, 0 failures (0.23s)
🔗 Integration Tests: 14 examples, 0 failures (0.02s)
✅ Total: 155 examples, 0 failures
```

## 🔧 Test Types

### Unit Tests (spec/unit/)
- **Purpose**: Fast feedback, isolated component testing
- **Setup**: Mocked dependencies, no real Vagrant loading
- **Speed**: ~0.23 seconds for 141 tests
- **Coverage**: 
  - Config validation and setup (32 examples)
  - FileLocker concurrency and thread safety (27 examples)
  - FileManager SSH file operations (39 examples)
  - SshConfigManager entry management (43 examples)

### Integration Tests (spec/integration/)
- **Purpose**: Real API verification, end-to-end testing
- **Setup**: Real Vagrant APIs, isolated file system environments
- **Speed**: ~0.02 seconds for 14 tests
- **Coverage**: IncludeManager SSH config manipulation, plugin markers

## 🛠 Helper Scripts

- `./test-unit.sh` - Run only unit tests with detailed output
- `./test-integration.sh` - Run only integration tests with detailed output  
- `./test-all.sh` - Run both test suites with summary

### 🎯 Test Strategy
- **Unit Tests**: Mock all external dependencies for speed and isolation
- **Integration Tests**: Use real Vagrant APIs with controlled environments
- **Comprehensive Coverage**: Every major component and method tested
- **Error Scenarios**: Both success and failure paths covered
