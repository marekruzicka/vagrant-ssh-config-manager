# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vagrant-ssh-config-manager/version'

Gem::Specification.new do |spec|
  spec.name          = 'vagrant-ssh-config-manager'
  spec.version       = VagrantPlugins::SshConfigManager::VERSION
  spec.authors       = ['Marek Ruzicka']
  spec.email         = ['marek.ruzicka@glide.sk']

  spec.summary       = 'Vagrant plugin that automatically manages SSH configurations'
  spec.description   = 'A Vagrant plugin that automatically manages SSH configurations. Creates and maintains SSH config entries when VMs are started and cleans them up when VMs are destroyed, with environment isolation and file locking support.'
  spec.homepage      = 'https://github.com/marekruzicka/vagrant-ssh-config-manager'
  spec.license       = 'MIT'

  spec.metadata['documentation_uri'] = 'https://rubydoc.info/github/marekruzicka/vagrant-ssh-config-manager/main'
  spec.metadata['source_code_uri']   = 'https://github.com/marekruzicka/vagrant-ssh-config-manager'
  spec.metadata['changelog_uri']     = 'https://github.com/marekruzicka/vagrant-ssh-config-manager/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGems gemspec, but not Git submodules.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features|tasks|.github|.ai)/}) }
  end
  spec.require_paths = ['lib']

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-mocks', '~> 3.0'
  spec.add_development_dependency 'simplecov', '~> 0.21'

  # Ensure compatibility with supported Ruby versions
  spec.required_ruby_version = '>= 2.6.0'

  # Plugin metadata for Vagrant
  spec.metadata['vagrant_plugin'] = 'true'
end
