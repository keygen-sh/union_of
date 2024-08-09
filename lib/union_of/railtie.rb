# frozen_string_literal

require_relative 'macro'
require_relative 'preloader'
require_relative 'readonly_association_proxy'

module UnionOf
  module ReflectionExtension
    def add_union_reflection(model, name, reflection)
      model.union_reflections = model.union_reflections.merge(name.to_s => reflection)
    end

    private

    def reflection_class_for(macro)
      case macro
      when :union_of
        UnionOf::Reflection
      else
        super
      end
    end
  end

  module MacroReflectionExtension
    def through_union_of? = false
    def union_of?         = false
  end

  module RuntimeReflectionExtension
    delegate :union_of?, :union_sources, to: :@reflection
    delegate :name, :active_record_primary_key, to: :@reflection # FIXME(ezekg)
  end

  module ActiveRecordExtensions
    extend ActiveSupport::Concern

    included do
      include UnionOf::Macro

      class_attribute :union_reflections, instance_writer: false, default: {}
    end

    class_methods do
      def reflect_on_all_unions = union_reflections.values
      def reflect_on_union(union)
        union_reflections[union.to_s]
      end
    end
  end

  module ThroughReflectionExtension
    delegate :union_of?, :union_sources, to: :source_reflection
    delegate :join_scope, to: :source_reflection

    def through_union_of? = through_reflection.union_of? || through_reflection.through_union_of?
  end

  module AssociationExtension
    def scope
      if reflection.union_of? || reflection.through_union_of?
        UnionOf::Scope.create.scope(self)
      else
        super
      end
    end
  end

  module PreloaderExtension
    def preloader_for(reflection)
      if reflection.union_of?
        UnionOf::Preloader::Association
      else
        super
      end
    end
  end

  module DelegationExtension
    def delegated_classes
      super << UnionOf::ReadonlyAssociationProxy
    end
  end

  module JoinAssociationExtension
    # Overloads Rails internals to prepend our left outer joins onto the join chain since Rails
    # unfortunately does not do this for us (it can do inner joins via the LeadingJoin arel
    # node, but it can't do outer joins because there is no LeadingOuterJoin node).
    def join_constraints(foreign_table, foreign_klass, join_type, alias_tracker)
      chain = reflection.chain.reverse
      joins = super

      # FIXME(ezekg) This is inefficient (we're recreating reflection scopes).
      chain.zip(joins).each do |reflection, join|
        klass = reflection.klass
        table = join.left

        if reflection.union_of?
          scope = reflection.join_scope(table, foreign_table, foreign_klass, alias_tracker)
          arel  = scope.arel(alias_tracker.aliases)

          # Splice union dependencies, i.e. left joins, into the join chain. This is the least
          # intrusive way of doing this, since we don't want to overload AR internals.
          unless arel.join_sources.empty?
            index = joins.index(join)

            unless (constraints = arel.constraints).empty?
              right = join.right

              right.expr = constraints # updated aliases
            end

            joins.insert(index, *arel.join_sources)
          end
        end

        # The current table in this iteration becomes the foreign table in the next
        foreign_table, foreign_klass = table, klass
      end

      joins
    end
  end

  ActiveSupport.on_load :active_record do
    include ActiveRecordExtensions

    ActiveRecord::Reflection.singleton_class.prepend(ReflectionExtension)
    ActiveRecord::Reflection::MacroReflection.prepend(MacroReflectionExtension)
    ActiveRecord::Reflection::RuntimeReflection.prepend(RuntimeReflectionExtension)
    ActiveRecord::Reflection::ThroughReflection.prepend(ThroughReflectionExtension)
    ActiveRecord::Associations::Association.prepend(AssociationExtension)
    ActiveRecord::Associations::JoinDependency::JoinAssociation.prepend(JoinAssociationExtension)
    ActiveRecord::Associations::Preloader::Branch.prepend(PreloaderExtension)
    ActiveRecord::Delegation.singleton_class.prepend(DelegationExtension)
  end
end
