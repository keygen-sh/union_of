# frozen_string_literal: true

require_relative 'readonly_association'
require_relative 'scope'

module UnionOf
  class Association < UnionOf::ReadonlyAssociation
    def skip_statement_cache?(...) = true # doesn't work with cache
    def association_scope
      return if
        klass.nil?

      @association_scope ||= UnionOf::Scope.create.scope(self)
    end
  end
end
