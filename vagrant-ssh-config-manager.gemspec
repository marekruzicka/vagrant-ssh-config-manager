lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "vagrant-ssh-config-manager/version"

Gem::Specification.new do |spec|
  spec.name          = "vagrant-ssh-config-manager"
  spec.version       = VagrantPlugins::SshConfigManager::VERSION
  spec.authors       = ["Vagrant SSH Config Manager Team"]
  spec.email         = ["team@example.com"]

  spec.summary       = "Vagrant plugin that automatically manages SSH configurations"
  spec.description   = "A Vagrant plugin that automatically manages SSH configurations by leveraging Vagrant's internal SSH knowledge. Creates and maintains SSH config entries when VMs are started and cleans them up when VMs are destroyed, with environment isolation and file locking support."
  spec.homepage      = "https://github.com/example/vagrant-ssh-config-manager"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/example/vagrant-ssh-config-manager"
    spec.metadata["changelog_uri"] = "https://github.com/example/vagrant-ssh-config-manager/blob/main/CHANGELOG.md"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGems gemspec, but not Git submodules.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "vagrant", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-mocks", "~> 3.0"
  spec.add_development_dependency "simplecov", "~> 0.21"

  # Ensure compatibility with supported Ruby versions
  spec.required_ruby_version = ">= 2.6.0"

  # Plugin metadata for Vagrant
  spec.metadata["vagrant_plugin"] = "true"
end
