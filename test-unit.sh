#!/bin/bash
# Run unit tests only (fast, isolated)
echo "🚀 Running Unit Tests..."
bundle exec rspec spec/unit/ --format documentation
