# GitHub Actions Setup for Gem Publishing

This workflow automatically builds and publishes the `vagrant-ssh-config-manager` gem to RubyGems.

## Setup Instructions

### 1. RubyGems API Key

You need to configure a RubyGems API key as a GitHub secret:

1. Go to [RubyGems.org](https://rubygems.org) and sign in
2. Go to your profile settings → API Keys
3. Create a new API key with "Push rubygem" permission
4. In your GitHub repository, go to Settings → Secrets and variables → Actions
5. Create a new repository secret named `RUBYGEMS_API_KEY` with your API key as the value

### 2. GitHub Token

The workflow uses the default `GITHUB_TOKEN` which is automatically provided by GitHub Actions. No additional setup is required.

## How the Workflow Works

### Manual Trigger (workflow_dispatch)

- Go to Actions tab in GitHub → "Build and Publish Gem" workflow → "Run workflow"
- Enter the desired version (e.g., "0.8.4")
- The workflow will:
  1. Run tests across multiple Ruby versions (2.7, 3.0, 3.1, 3.2, 3.3)
  2. Run RuboCop for code quality checks
  3. Update the version file (`lib/vagrant-ssh-config-manager/version.rb`)
  4. Commit the version change to main branch
  5. Create a git tag
  6. Build the gem
  7. Publish to RubyGems (if version doesn't already exist)
  8. Create a GitHub release with the gem file attached

### Automatic Trigger (push to main)

- Triggers automatically when code is pushed/merged to the main branch
- Uses the current version from `lib/vagrant-ssh-config-manager/version.rb`
- Follows the same build and publish process
- Will only publish if the current version doesn't already exist on RubyGems

### Test Branch Trigger (push to test-* branches)

- Triggers automatically when code is pushed to any branch starting with `test-` (e.g., `test-feature`, `test-bugfix`)
- Runs the full test suite across multiple Ruby versions
- Builds the gem to verify it can be packaged correctly
- **Does NOT publish** to RubyGems or create releases
- Useful for testing changes before merging to main

## Features

- **Duplicate Prevention**: Checks if a version already exists on RubyGems before publishing
- **Git Tag Management**: Creates git tags for releases automatically
- **GitHub Releases**: Creates GitHub releases with release notes and gem files
- **Multi-Ruby Testing**: Tests across multiple Ruby versions for compatibility
- **Code Quality**: Runs RuboCop for style and quality checks
- **Smart Skipping**: Skips workflow runs for documentation-only changes

## File Structure

```
.github/
└── workflows/
    └── build-and-publish.yml
```

## Troubleshooting

- If the workflow fails due to permissions, ensure the repository has "Read and write permissions" enabled in Settings → Actions → General → Workflow permissions
- If RubyGems publishing fails, verify the `RUBYGEMS_API_KEY` secret is correctly set
- If git operations fail, the workflow uses the default GitHub token which should have sufficient permissions for the repository
