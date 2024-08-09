# frozen_string_literal: true

require 'active_support'
require 'active_record'

require_relative 'union_of/association'
require_relative 'union_of/builder'
require_relative 'union_of/macro'
require_relative 'union_of/preloader'
require_relative 'union_of/readonly_association_proxy'
require_relative 'union_of/readonly_association'
require_relative 'union_of/reflection'
require_relative 'union_of/scope'
require_relative 'union_of/version'
require_relative 'union_of/railtie'

module UnionOf
  class Error < ActiveRecord::ActiveRecordError; end

  class ReadonlyAssociationError < Error
    def initialize(owner, reflection)
      super("Cannot modify association '#{owner.class.name}##{reflection.name}' because it is read-only")
    end
  end
end
