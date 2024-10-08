# frozen_string_literal: true

require_relative 'lib/union_of/version'

Gem::Specification.new do |spec|
  spec.name        = 'union_of'
  spec.version     = UnionOf::VERSION
  spec.authors     = ['Zeke Gabrielse']
  spec.email       = ['oss@keygen.sh']
  spec.summary     = 'Create associations that combine multiple Active Record associations using a SQL UNION under the hood.'
  spec.description = 'Create associations that combine multiple Active Record associations using a SQL UNION under the hood, with full support for joins, preloading and eager loading on the union association, as well as through-union associations.'
  spec.homepage    = 'https://github.com/keygen-sh/union_of'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 3.1'
  spec.files                 = %w[LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md README.md] + Dir.glob('lib/**/*')
  spec.require_paths         = ['lib']

  spec.add_dependency 'rails', '>= 7.0'

  spec.add_development_dependency 'rspec-rails'
  spec.add_development_dependency 'temporary_tables', '~> 1.0'
  spec.add_development_dependency 'sql_matchers', '~> 1.0'
  spec.add_development_dependency 'sqlite3', '~> 1.4'
  spec.add_development_dependency 'mysql2'
  spec.add_development_dependency 'pg'
end
