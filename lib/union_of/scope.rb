# frozen_string_literal: true

module UnionOf
  class Scope < ActiveRecord::Associations::AssociationScope
    private

    def last_chain_scope(scope, reflection, owner)
      return super unless reflection.union_of?

      foreign_klass = reflection.klass
      foreign_table = reflection.aliased_table
      primary_key   = reflection.active_record_primary_key

      sources = reflection.union_sources.map do |source|
        association = owner.association(source)

        association.scope.select(association.reflection.active_record_primary_key)
                         .unscope(:order)
                         .arel
      end

      unions = sources.compact.reduce(nil) do |left, right|
        if left
          Arel::Nodes::Union.new(left, right)
        else
          right
        end
      end

      # We can simplify the query if the scope class is the same as our foreign class
      if scope.klass == foreign_klass
        scope.where!(
          foreign_table[primary_key].in(
            foreign_table.project(foreign_table[primary_key])
                         .from(
                           Arel::Nodes::TableAlias.new(unions, foreign_table.name),
                         ),
          ),
        )
      else
        # FIXME(ezekg) Selecting IDs in a separate query is faster than a subquery
        #              selecting IDs, or an EXISTS subquery, or even a
        #              materialized CTE. Not sure why...
        ids = foreign_klass.find_by_sql(
                             foreign_table.project(foreign_table[primary_key])
                                          .from(
                                            Arel::Nodes::TableAlias.new(unions, foreign_table.name),
                                          ),
                           )
                           .pluck(
                             primary_key,
                           )

        scope.where!(
          foreign_table[primary_key].in(ids),
        )
      end

      scope.merge!(
        scope.default_scoped,
      )

      scope
    end

    def next_chain_scope(scope, reflection, next_reflection)
      return super unless reflection.union_of?

      klass         = reflection.klass
      table         = klass.arel_table
      foreign_klass = next_reflection.klass
      foreign_table = foreign_klass.arel_table

      # This holds our union's constraints. For example, if we're unioning across 3
      # tables, then this will hold constraints for all 3 of those tables, so that
      # the join on our target table mirrors the union of all 3 associations.
      foreign_constraints = []

      reflection.union_sources.each do |union_source|
        union_reflection = foreign_klass.reflect_on_association(union_source)

        if union_reflection.through_reflection?
          through_reflection = union_reflection.through_reflection
          through_table      = through_reflection.klass.arel_table

          scope.left_outer_joins!(
            through_reflection.name,
          )

          foreign_constraints << foreign_table[through_reflection.join_foreign_key].eq(through_table[through_reflection.join_primary_key])
        else
          foreign_constraints << foreign_table[union_reflection.join_foreign_key].eq(table[union_reflection.join_primary_key])
        end
      end

      # Flatten union constraints and add any default constraints
      foreign_constraint = unless (where_clause = foreign_klass.default_scoped.where_clause).empty?
                             where_clause.ast.and(foreign_constraints.reduce(&:or))
                           else
                             foreign_constraints.reduce(&:or)
                           end

      scope.joins!(
        Arel::Nodes::InnerJoin.new(
          foreign_table,
          Arel::Nodes::On.new(
            foreign_constraint,
          ),
        ),
      )

      # FIXME(ezekg) Why is this needed? Should be handled automatically...
      scope.merge!(
        scope.default_scoped,
      )

      scope
    end

    # NOTE(ezekg) This overloads our scope's joins to not use an Arel::Nodes::LeadingJoin node.
    def join(table, constraint)
      Arel::Nodes::InnerJoin.new(table, Arel::Nodes::On.new(constraint))
    end
  end
end
