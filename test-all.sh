#!/bin/bash
# Run all tests
echo "🎯 Running Whole Test Suite..."
echo ""
echo "📦 Unit Tests (Fast, Mocked):"
bundle exec rspec spec/unit/ --format progress
echo ""
echo "🔗 Integration Tests (Real APIs):"
bundle exec rspec spec/integration/ --format progress
echo ""
echo "✅ Testing complete!"
