# frozen_string_literal: true

require_relative 'builder'

module UnionOf
  module Macro
    extend ActiveSupport::Concern

    class_methods do
      def union_of(name, scope = nil, **options, &extension)
        reflection = UnionOf::Builder.build(self, name, scope, options, &extension)

        ActiveRecord::Reflection.add_union_reflection(self, name, reflection)
        ActiveRecord::Reflection.add_reflection(self, name, reflection)
      end

      def has_many(name, scope = nil, **options, &extension)
        if sources = options.delete(:union_of)
          union_of(name, scope, **options.merge(sources:), &extension)
        else
          super
        end
      end
    end
  end
end
