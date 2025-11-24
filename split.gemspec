# frozen_string_literal: true

require_relative 'lib/split/version'

Gem::Specification.new do |spec|
  spec.name = 'split-rb'
  spec.version = Split::VERSION
  spec.authors = ['ScionX']
  spec.email = ['contact@scionx.com']

  spec.summary = 'A Ruby gem for interacting with 0xSplits V2 protocol contracts'
  spec.description = 'This gem provides functionality to create, manage, and interact with 0xSplits V2 protocol contracts for automated revenue distribution.'
  spec.homepage = 'https://github.com/ScionX/split'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{lib,constants}/**/*', 'README.md', 'LICENSE', 'CHANGELOG.md']
  end
  
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_runtime_dependency 'eth', '~> 0.5'
  spec.add_runtime_dependency 'graphql-client', '~> 0.18'
  spec.add_runtime_dependency 'pimlico', '~> 0.1'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'rubocop-performance', '~> 1.0'
  spec.add_development_dependency 'rubocop-rake', '~> 0.6'
end
