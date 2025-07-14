#!/bin/bash
# Run integration tests only (real APIs)
echo "🔧 Running Integration Tests..."
bundle exec rspec spec/integration/ --format documentation
