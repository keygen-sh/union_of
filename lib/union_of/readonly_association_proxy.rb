# frozen_string_literal: true

module UnionOf
  class ReadonlyAssociationProxy < ActiveRecord::Associations::CollectionProxy
    MUTATION_METHODS = %i[
      insert insert! insert_all insert_all!
      build new create create!
      upsert upsert_all update_all update! update
      delete destroy destroy_all delete_all
    ]

    MUTATION_METHODS.each do |method_name|
      define_method method_name do |*, **|
        raise UnionOf::ReadonlyAssociationError.new(@association.owner, @association.reflection)
      end
    end
  end
end
