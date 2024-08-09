# frozen_string_literal: true

module UnionOf
  class ReadonlyAssociation < ActiveRecord::Associations::CollectionAssociation
    MUTATION_METHODS = %i[
      writer ids_writer
      insert_record build_record
      destroy_all delete_all delete_records
      update_all concat_records
    ]

    MUTATION_METHODS.each do |method_name|
      define_method method_name do |*, **|
        raise UnionOf::ReadonlyAssociationError.new(owner, reflection)
      end
    end

    def reader
      ensure_klass_exists!

      if stale_target?
        reload
      end

      @proxy ||= UnionOf::ReadonlyAssociationProxy.create(klass, self)
      @proxy.reset_scope
    end

    def count_records
      count = scope.count(:all)

      if count.zero?
        target.select!(&:new_record?)
        loaded!
      end

      [association_scope.limit_value, count].compact.min
    end
  end
end
