# Hybrid Testing for vagrant-ssh-config-manager

This project uses a **hybrid testing approach** that combines fast unit tests with comprehensive integration tests.

## 🚀 Quick Start

```bash
# Canonical full-suite command
bundle exec rake

# Individual suites
bundle exec rake spec:unit
bundle exec rake spec:integration

# Helper scripts for detailed output:
./test-unit.sh           # Unit tests with documentation format
./test-integration.sh    # Integration tests with documentation format
./test-all.sh            # Both suites with progress format
```

`bundle exec rake` is the supported full-suite command. It runs unit and integration specs in separate Ruby processes because integration specs load real Vagrant while unit specs mock some Vagrant constants.

## 📁 Test Structure

```
spec/
├── unit_helper.rb           # Minimal setup for unit tests
├── integration_helper.rb    # Real Vagrant setup for integration tests
├── unit/                    # Fast, isolated unit tests
│   ├── config_spec.rb          # ✅ Config class (32 examples)
│   ├── file_locker_spec.rb     # ✅ FileLocker class (27 examples)
│   └── file_manager_spec.rb    # ✅ FileManager class (39 examples)
└── integration/             # Real API integration tests
    └── include_manager_spec.rb # ✅ IncludeManager (14 examples)
```

## ✅ Current Test Status

- **Unit Tests**: run with `bundle exec rake spec:unit`
- **Integration Tests**: run with `bundle exec rake spec:integration`
- **Full Suite**: run with `bundle exec rake`
- **Combined Runtime**: ~0.25 seconds (extremely fast!)

## 🚀 Performance Metrics

```bash
$ bundle exec rake
# Runs unit specs, then integration specs, in separate Ruby processes
```

## 🔧 Test Types

### Unit Tests (spec/unit/)
- **Purpose**: Fast feedback, isolated component testing
- **Setup**: Mocked dependencies, no real Vagrant loading
- **Command**: `bundle exec rake spec:unit`
- **Coverage**: 
  - Config validation and setup
  - FileLocker concurrency and thread safety
  - FileManager SSH file operations

### Integration Tests (spec/integration/)
- **Purpose**: Real API verification, end-to-end testing
- **Setup**: Real Vagrant APIs, isolated file system environments
- **Command**: `bundle exec rake spec:integration`
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
