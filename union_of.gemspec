# frozen_string_literal: true

require_relative "lib/union_of/version"

Gem::Specification.new do |spec|
  spec.name        = 'union_of'
  spec.version     = UnionOf::VERSION
  spec.authors     = ['Zeke Gabrielse']
  spec.email       = ['oss@keygen.sh']
  spec.summary     = 'Define UNION associations for Active Record models.'
  spec.description = 'Define associations that are a union of other associations on an Active Record model, using a SQL UNION, with full support for joins on the union association.'
  spec.homepage    = 'https://github.com/keygen-sh/union_of'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 3.1'
  spec.files                 = %w[LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md README.md] + Dir.glob('lib/**/*')
  spec.require_paths         = ['lib']

  spec.add_dependency 'rails', '>= 6.0'

  spec.add_development_dependency 'rspec-rails'
end
