# frozen_string_literal: true

require 'union_of'
require 'temporary_tables'
require 'sql_matchers'
require 'active_support'
require 'active_support/testing/time_helpers'
require 'active_record'
require 'logger'

ActiveRecord::Base.logger = Logger.new(STDOUT) if ENV.key?('DEBUG')
ActiveRecord::Base.establish_connection(
  ENV.fetch('DATABASE_URL') { 'sqlite3::memory:' },
)

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
  config.include TemporaryTables::Methods
  config.include SqlMatchers::Methods

  config.expect_with(:rspec) { _1.syntax = :expect }
  config.disable_monkey_patching!

  config.around :each, :unprepared_statements do |example|
    ActiveRecord::Base.connection.unprepared_statement { example.run }
  end
end
