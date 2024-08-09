# frozen_string_literal: true

module UnionOf
  class Reflection < ActiveRecord::Reflection::AssociationReflection
    attr_reader :union_sources

    def initialize(...)
      super

      @union_sources = @options[:sources]
    end

    def macro             = :union_of
    def union_of?         = true
    def collection?       = true
    def association_class = UnionOf::Association
    def union_reflections = union_sources.collect { active_record.reflect_on_association(_1) }

    def join_scope(table, foreign_table, foreign_klass, alias_tracker = nil)
      predicate_builder = predicate_builder(table)
      scope_chain_items = join_scopes(table, predicate_builder)
      klass_scope       = klass_join_scope(table, predicate_builder)

      # This holds our union's constraints. For example, if we're unioning across 3
      # tables, then this will hold constraints for all 3 of those tables, so that
      # the join on our target table mirrors the union of all 3 associations.
      foreign_constraints = []

      union_sources.each do |union_source|
        union_reflection = foreign_klass.reflect_on_association(union_source)

        if union_reflection.through_reflection?
          source_reflection  = union_reflection.source_reflection
          through_reflection = union_reflection.through_reflection
          through_klass      = through_reflection.klass
          through_table      = through_klass.arel_table

          # Alias table if we're provided with an alias tracker (i.e. via our #join_constraints overload)
          unless alias_tracker.nil?
            through_table = alias_tracker.aliased_table_for(through_table) do
              through_reflection.alias_candidate(union_source)
            end
          end

          # Create base join constraints and add default constraints if available
          through_constraint = through_table[through_reflection.join_primary_key].eq(
            foreign_table[through_reflection.join_foreign_key],
          )

          unless (where_clause = through_klass.default_scoped.where_clause).empty?
            through_constraint = where_clause.ast.and(through_constraint)
          end

          klass_scope.joins!(
            Arel::Nodes::OuterJoin.new(
              through_table,
              Arel::Nodes::On.new(through_constraint),
            ),
          )

          foreign_constraints << table[source_reflection.join_primary_key].eq(through_table[source_reflection.join_foreign_key])
        else
          foreign_constraints << table[union_reflection.join_primary_key].eq(foreign_table[union_reflection.join_foreign_key])
        end
      end

      unless foreign_constraints.empty?
        foreign_constraint = foreign_constraints.reduce(&:or)

        klass_scope.where!(foreign_constraint)
      end

      unless scope_chain_items.empty?
        scope_chain_items.reduce(klass_scope) do |scope, item|
          scope.merge!(item) # e.g. default scope constraints
        end

        # FIXME(ezekg) Wrapping the where clause in a grouping node so that Rails
        #              doesn't append our left outer joins a second time. This is
        #              because internally, during joining in #join_constraints,
        #              if Rails sees an Arel::Nodes::And node with predicates that
        #              don't match the current table, it'll concat all join
        #              sources. We don't want that, thus the hack.
        klass_scope.where_clause = ActiveRecord::Relation::WhereClause.new(
          [Arel::Nodes::Grouping.new(klass_scope.where_clause.ast)],
        )
      end

      klass_scope
    end

    # FIXME(ezekg) scope cache is borked
    def association_scope_cache(...) = raise NotImplementedError

    def deconstruct_keys(keys) = { name:, options: }
  end
end
