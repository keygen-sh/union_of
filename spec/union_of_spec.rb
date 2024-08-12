# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UnionOf do
  temporary_table :account do |t|
    t.timestamps
  end

  temporary_table :user do |t|
    t.references :account, null: true
    t.string :email
    t.index :email, unique: true
    t.timestamps
  end

  temporary_table :products do |t|
    t.references :account, null: true
    t.timestamps
  end

  temporary_table :licenses do |t|
    t.references :account, null: true
    t.references :product, null: true
    t.references :owner, null: true
    t.timestamp :last_activity_at
    t.timestamps
  end

  temporary_table :license_users do |t|
    t.references :account, null: true
    t.references :license, null: false
    t.references :user, null: false
    t.timestamps
  end

  temporary_table :machines do |t|
    t.references :account, null: true
    t.references :license, null: false
    t.references :owner, null: true
    t.timestamps
  end

  temporary_table :hardwares do |t|
    t.references :account, null: true
    t.references :machine, null: false
    t.timestamps
  end

  temporary_table :releases do |t|
    t.references :account, null: true
    t.references :product, null: false
    t.string :version
    t.timestamps
  end

  temporary_table :artifact do |t|
    t.references :account, null: true
    t.references :release, null: false
    t.string :filename
    t.timestamps
  end

  temporary_model :account do
    has_many :licenses
    has_many :license_users
    has_many :machines
    has_many :users
  end

  temporary_model :product do
    belongs_to :account, optional: true
    has_many :licenses
    has_many :users, -> { distinct }, through: :licenses
  end

  temporary_model :license do
    belongs_to :account, optional: true
    belongs_to :product, optional: true
    belongs_to :owner, class_name: 'User', optional: true
    has_many :license_users
    has_many :licensees, through: :license_users, source: :user
    has_many :users, union_of: %i[owner licensees]
    has_many :machines
  end

  temporary_model :license_users do
    belongs_to :account, optional: true
    belongs_to :license
    belongs_to :user
  end

  temporary_model :machine do
    belongs_to :account, optional: true
    belongs_to :owner, class_name: 'User', optional: true
    belongs_to :license
    has_many :users, through: :license
    has_many :hardwares
  end

  temporary_model :hardware do
    belongs_to :account, optional: true
    belongs_to :machine
  end

  temporary_model :release do
    belongs_to :account, optional: true
    belongs_to :product
    has_many :licenses, through: :product
    has_many :users, through: :product
    has_many :artifacts
  end

  temporary_model :artifact do
    belongs_to :account, optional: true
    belongs_to :release
    has_one :product, through: :release
  end

  temporary_model :user do
    include UnionOf::Macro

    belongs_to :account, optional: true
    has_many :owned_licenses, class_name: 'License', foreign_key: :owner_id
    has_many :license_users
    has_many :shared_licenses, through: :license_users, source: :license
    has_many :licenses, union_of: %i[owned_licenses shared_licenses] do
      def owned = where(owner: proxy_association.owner)
    end
    has_many :teammates, -> me { distinct.excluding(me) }, through: :licenses, source: :users
    has_many :products, -> { distinct }, through: :licenses
    has_many :machines, -> { distinct }, through: :licenses do
      def owned = where(owner: proxy_association.owner)
    end
    has_many :hardwares, -> { distinct }, through: :machines do
      def owned = where(owner: proxy_association.owner)
    end
    has_many :any_active_licenses, -> {
      where(<<~SQL.squish, start_date: 90.days.ago)
        licenses.created_at >= :start_date OR (licenses.last_activity_at IS NOT NULL AND licenses.last_activity_at >= :start_date)
      SQL
    },
      union_of: %i[owned_licenses shared_licenses],
      class_name: 'License'
  end

  it 'should create an association reflection' do
    expect(User.reflect_on_all_associations).to satisfy { |associations|
      associations in [
        *,
        UnionOf::Reflection(
          name: :licenses,
          options: {
            sources: %i[owned_licenses shared_licenses],
          },
        ),
        *
      ]
    }
  end

  it 'should create a union reflection' do
    expect(User.reflect_on_all_unions).to satisfy { |unions|
      unions in [
        *,
        UnionOf::Reflection(
          name: :licenses,
          options: {
            sources: %i[owned_licenses shared_licenses],
          },
        ),
        *
      ]
    }
  end

  it 'should be a relation' do
    user = User.create

    expect(user.licenses).to be_an ActiveRecord::Relation
  end

  it 'should return the correct relations' do
    user_1           = User.create
    user_2           = User.create
    user_3           = User.create
    user_4           = User.create

    owned_license_1  = License.create(owner: user_1)
    owned_license_2  = License.create(owner: user_2)
    owned_license_3  = License.create(owner: user_3)

    shared_license_1 = License.create
    shared_license_2 = License.create
    shared_license_3 = License.create
    shared_license_4 = License.create

    license_user_1   = LicenseUser.create(license: shared_license_1, user: user_1)
    license_user_2   = LicenseUser.create(license: shared_license_2, user: user_1)
    license_user_3   = LicenseUser.create(license: shared_license_3, user: user_2)
    license_user_4   = LicenseUser.create(license: shared_license_3, user: user_1)
    license_user_5   = LicenseUser.create(license: shared_license_4, user: user_2)

    expect(user_1.licenses.to_a).to eq [owned_license_1, shared_license_1, shared_license_2, shared_license_3]
    expect(user_2.licenses.to_a).to eq [owned_license_2, shared_license_3, shared_license_4]
    expect(user_3.licenses.to_a).to eq [owned_license_3]
    expect(user_4.licenses.to_a).to eq []
  end

  it 'should return the correct relation ids' do
    user_1           = User.create
    user_2           = User.create
    user_3           = User.create
    user_4           = User.create

    owned_license_1  = License.create(owner: user_1)
    owned_license_2  = License.create(owner: user_2)
    owned_license_3  = License.create(owner: user_3)

    shared_license_1 = License.create
    shared_license_2 = License.create
    shared_license_3 = License.create
    shared_license_4 = License.create

    license_user_1   = LicenseUser.create(license: shared_license_1, user: user_1)
    license_user_2   = LicenseUser.create(license: shared_license_2, user: user_1)
    license_user_3   = LicenseUser.create(license: shared_license_3, user: user_2)
    license_user_4   = LicenseUser.create(license: shared_license_3, user: user_1)
    license_user_5   = LicenseUser.create(license: shared_license_4, user: user_2)

    expect(user_1.license_ids).to eq [owned_license_1.id, shared_license_1.id, shared_license_2.id, shared_license_3.id]
    expect(user_2.license_ids).to eq [owned_license_2.id, shared_license_3.id, shared_license_4.id]
    expect(user_3.license_ids).to eq [owned_license_3.id]
    expect(user_4.license_ids).to eq []
  end

  it 'should be a union' do
    user = User.create

    expect(user.licenses.to_sql).to match_sql <<~SQL.squish
      SELECT
        "licenses".*
      FROM
        "licenses"
      WHERE
        "licenses"."id" IN (
          SELECT
            "licenses"."id"
          FROM
            (
              (
                SELECT
                  "licenses"."id"
                FROM
                  "licenses"
                WHERE
                  "licenses"."owner_id" = #{user.id}
              )
              UNION
              (
                SELECT
                  "licenses"."id"
                FROM
                  "licenses"
                  INNER JOIN "license_users" ON "licenses"."id" = "license_users"."license_id"
                WHERE
                  "license_users"."user_id" = #{user.id}
              )
            ) "licenses"
        )
    SQL
  end

  it 'should not raise on shallow join' do
    expect { User.joins(:licenses).to_a }.to_not raise_error
  end

  it 'should produce a shallow join' do
    user = User.create

    expect(License.joins(:users).where(users: { id: user }).to_sql).to match_sql <<~SQL.squish
      SELECT
        "licenses".*
      FROM
        "licenses"
        LEFT OUTER JOIN "license_users" ON "license_users"."license_id" = "licenses"."id"
        INNER JOIN "users" ON (
          "users"."id" = "licenses"."owner_id"
          OR "users"."id" = "license_users"."user_id"
        )
      WHERE
        "users"."id" = #{user.id}
    SQL
  end

  it 'should not raise on deep join' do
    expect { User.joins(:machines).to_a }.to_not raise_error
  end

  it 'should produce a union join' do
    expect(User.joins(:machines).to_sql).to match_sql <<~SQL.squish
      SELECT
        "users".*
      FROM
        "users"
        LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
        INNER JOIN "licenses" ON (
          "licenses"."owner_id" = "users"."id"
          OR "licenses"."id" = "license_users"."license_id"
        )
        INNER JOIN "machines" ON "machines"."license_id" = "licenses"."id"
    SQL
  end

  it 'should produce multiple joins' do
    expect(User.joins(:licenses, :machines).to_sql).to match_sql <<~SQL.squish
      SELECT
        "users".*
      FROM
        "users"
        LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
        INNER JOIN "licenses" ON (
          "licenses"."owner_id" = "users"."id"
          OR "licenses"."id" = "license_users"."license_id"
        )
        LEFT OUTER JOIN "license_users" "license_users_shared_licenses" ON "license_users_shared_licenses"."user_id" = "users"."id"
        INNER JOIN "licenses" "licenses_users_join" ON (
          "licenses_users_join"."owner_id" = "users"."id"
          OR "licenses_users_join"."id" = "license_users_shared_licenses"."license_id"
        )
        INNER JOIN "machines" ON "machines"."license_id" = "licenses_users_join"."id"
    SQL
  end

  it 'should join with association scopes' do
    travel_to Time.parse('2024-03-08 01:23:45 UTC') do |t|
      expect(User.joins(:any_active_licenses).to_sql).to match_sql <<~SQL.squish
        SELECT
          "users".*
        FROM
          "users"
          LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
          INNER JOIN "licenses" ON (
            (
              "licenses"."owner_id" = "users"."id"
              OR "licenses"."id" = "license_users"."license_id"
            )
            AND (
              licenses.created_at >= '2023-12-09 01:23:45'
              OR (
                licenses.last_activity_at IS NOT NULL
                AND licenses.last_activity_at >= '2023-12-09 01:23:45'
              )
            )
          )
      SQL
    end
  end

  it 'should preload with association scopes', :unprepared_statements do
    user           = User.create
    owned_license  = License.create(owner: user)
    shared_license = License.create
    license_user   = LicenseUser.create(license: shared_license, user:)

    travel_to Time.parse('2024-03-08 01:23:45 UTC') do |t|
      expect { User.preload(:any_active_licenses).where(id: user.id) }.to(
        match_queries(count: 4) do |(first, second, third, fourth)|
          expect(first).to match_sql <<~SQL.squish
            SELECT
              "users".*
            FROM
              "users"
            WHERE
              "users"."id" = #{user.id}
          SQL

          expect(second).to match_sql <<~SQL.squish
            SELECT
              "licenses".*
            FROM
              "licenses"
            WHERE
              (
                licenses.created_at >= '2023-12-09 01:23:45'
                OR (
                  licenses.last_activity_at IS NOT NULL
                  AND licenses.last_activity_at >= '2023-12-09 01:23:45'
                )
              )
              AND "licenses"."owner_id" = #{user.id}
          SQL

          expect(third).to match_sql <<~SQL.squish
            SELECT
              "license_users".*
            FROM
              "license_users"
            WHERE
              "license_users"."user_id" = #{user.id}
          SQL

          expect(fourth).to match_sql <<~SQL.squish
            SELECT
              "licenses".*
            FROM
              "licenses"
            WHERE
              (
                licenses.created_at >= '2023-12-09 01:23:45'
                OR (
                  licenses.last_activity_at IS NOT NULL
                  AND licenses.last_activity_at >= '2023-12-09 01:23:45'
                )
              )
              AND "licenses"."id" = #{shared_license.id}
          SQL
        end
      )
    end
  end

  context 'with current account' do
    temporary_model :current, table_name: nil, base_class: ActiveSupport::CurrentAttributes do
      attribute :account
    end

    let(:account) { Account.create }

    # add a default scope using current account
    before do
      concern = Module.new do
        extend ActiveSupport::Concern

        included do
          default_scope { where(account: Current.account) }
        end
      end

      User.include(concern)
      License.include(concern)
      LicenseUser.include(concern)
      Machine.include(concern)
    end

    it 'should produce a query with default scopes', :unprepared_statements do
      user    = User.create(account:)
      license = License.create(owner: user, account:)
      machine = Machine.create(license:, account:)

      Current.account = account

      expect { user.machines }.to(
        match_queries(count: 2) do |queries|
          expect(queries.first).to match_sql <<~SQL.squish
            SELECT
              "licenses"."id"
            FROM
              (
                (
                  SELECT
                    "licenses"."id"
                  FROM
                    "licenses"
                  WHERE
                    "licenses"."account_id" = #{account.id}
                    AND "licenses"."owner_id" = #{user.id}
                )
                UNION
                (
                  SELECT
                    "licenses"."id"
                  FROM
                    "licenses"
                    INNER JOIN "license_users" ON "licenses"."id" = "license_users"."license_id"
                  WHERE
                    "licenses"."account_id" = #{account.id}
                    AND "license_users"."account_id" = #{account.id}
                    AND "license_users"."user_id" = #{user.id}
                )
              ) "licenses"
          SQL

          expect(queries.second).to match_sql <<~SQL.squish
            SELECT
              DISTINCT "machines".*
            FROM
              "machines"
              INNER JOIN "licenses" ON "machines"."license_id" = "licenses"."id"
            WHERE
              "licenses"."id" IN (#{license.id})
              AND "machines"."account_id" = #{account.id}
          SQL
        end
      )
    end

    it 'should produce a join with default scopes' do
      Current.account = account

      expect(User.joins(:machines).to_sql).to match_sql <<~SQL.squish
        SELECT
          "users".*
        FROM
          "users"
          LEFT OUTER JOIN "license_users" ON "license_users"."account_id" = #{account.id}
          AND "license_users"."user_id" = "users"."id"
          INNER JOIN "licenses" ON "licenses"."account_id" = #{account.id}
          AND (
            "licenses"."owner_id" = "users"."id"
            OR "licenses"."id" = "license_users"."license_id"
          )
          INNER JOIN "machines" ON "machines"."account_id" = #{account.id}
          AND "machines"."license_id" = "licenses"."id"
        WHERE
          "users"."account_id" = #{account.id}
      SQL
    end
  end

  it 'should produce a through has-many union query', :unprepared_statements do
    user    = User.create
    license = License.create(owner: user)
    machine = Machine.create(license:)

    expect { user.machines }.to(
      match_queries(count: 2) do |queries|
        expect(queries.first).to match_sql <<~SQL.squish
          SELECT
            "licenses"."id"
          FROM
            (
              (
                SELECT
                  "licenses"."id"
                FROM
                  "licenses"
                WHERE
                  "licenses"."owner_id" = #{user.id}
              )
              UNION
              (
                SELECT
                  "licenses"."id"
                FROM
                  "licenses"
                  INNER JOIN "license_users" ON "licenses"."id" = "license_users"."license_id"
                WHERE
                  "license_users"."user_id" = #{user.id}
              )
            ) "licenses"
        SQL

        expect(queries.second).to match_sql <<~SQL.squish
          SELECT
            DISTINCT "machines".*
          FROM
            "machines"
            INNER JOIN "licenses" ON "machines"."license_id" = "licenses"."id"
          WHERE
            "licenses"."id" IN (#{license.id})
        SQL
      end
    )
  end

  it 'should produce a through has-one union query' do
    user     = User.create
    license  = License.create(owner: user)
    machine  = Machine.create(license:)

    expect(machine.users.to_sql).to match_sql <<~SQL.squish
      SELECT
        "users".*
      FROM
        "users"
        LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
        INNER JOIN "licenses" ON (
          "licenses"."owner_id" = "users"."id"
          OR "licenses"."id" = "license_users"."license_id"
        )
      WHERE
        "licenses"."id" = #{license.id}
    SQL
  end

  it 'should produce a deep union join' do
    expect(User.joins(:hardwares).to_sql).to match_sql <<~SQL.squish
      SELECT
        "users".*
      FROM
        "users"
        LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
        INNER JOIN "licenses" ON (
          "licenses"."owner_id" = "users"."id"
          OR "licenses"."id" = "license_users"."license_id"
        )
        INNER JOIN "machines" ON "machines"."license_id" = "licenses"."id"
        INNER JOIN "hardwares" ON "hardwares"."machine_id" = "machines"."id"
    SQL
  end

  it 'should produce a deep union query', :unprepared_statements do
    user     = User.create
    license  = License.create(owner: user)
    machine  = Machine.create(license:)
    hardware = Hardware.create(machine:)

    expect { user.hardwares }.to(
      match_queries(count: 2) do |queries|
        expect(queries.first).to match_sql <<~SQL.squish
          SELECT
            "licenses"."id"
          FROM
            (
              (
                SELECT
                  "licenses"."id"
                FROM
                  "licenses"
                WHERE
                  "licenses"."owner_id" = #{user.id}
              )
              UNION
              (
                SELECT
                  "licenses"."id"
                FROM
                  "licenses"
                  INNER JOIN "license_users" ON "licenses"."id" = "license_users"."license_id"
                WHERE
                  "license_users"."user_id" = #{user.id}
              )
            ) "licenses"
        SQL

        expect(queries.second).to match_sql <<~SQL.squish
          SELECT
            DISTINCT "hardwares".*
          FROM
            "hardwares"
            INNER JOIN "machines" ON "hardwares"."machine_id" = "machines"."id"
            INNER JOIN "licenses" ON "machines"."license_id" = "licenses"."id"
          WHERE
            "licenses"."id" IN (#{license.id})
        SQL
      end
    )
  end

  it 'should produce a deeper union join' do
    expect(Product.joins(:users).to_sql).to match_sql <<~SQL.squish
      SELECT
        "products".*
      FROM
        "products"
        INNER JOIN "licenses" ON "licenses"."product_id" = "products"."id"
        LEFT OUTER JOIN "license_users" ON "license_users"."license_id" = "licenses"."id"
        INNER JOIN "users" ON (
          "users"."id" = "licenses"."owner_id"
          OR "users"."id" = "license_users"."user_id"
        )
    SQL
  end

  it 'should produce a deeper union query' do
    product = Product.create

    expect(product.users.to_sql).to match_sql <<~SQL.squish
      SELECT
        DISTINCT "users".*
      FROM
        "users"
        LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
        INNER JOIN "licenses" ON (
          "licenses"."owner_id" = "users"."id"
          OR "licenses"."id" = "license_users"."license_id"
        )
      WHERE
        "licenses"."product_id" = #{product.id}
    SQL
  end

  describe 'querying' do
    it 'should support querying a union' do
      user           = User.create
      other_user     = User.create
      owned_license  = License.create(owner: user)
      user_license_1 = License.create
      user_license_2 = License.create

      LicenseUser.create(license: owned_license, user: other_user)
      LicenseUser.create(license: user_license_1, user:)
      LicenseUser.create(license: user_license_2, user:)

      expect(owned_license.users.count).to eq 2
      expect(owned_license.users).to satisfy { _1.to_a in [user, other_user] }

      expect(user.licenses.count).to eq 3
      expect(user.licenses).to satisfy { _1.to_a in [owned_license, user_license_1, user_license_2] }
      expect(user.licenses.where.not(id: owned_license)).to satisfy { _1.to_a in [user_license_1, user_license_2] }
      expect(user.licenses.where(id: owned_license).count).to eq 1

      expect(other_user.licenses.count).to eq 1
      expect(other_user.licenses).to satisfy { _1.to_a in [owned_license] }
    end

    it 'should support querying a through union' do
      product_1 = Product.create
      product_2 = Product.create

      user           = User.create
      other_user     = User.create
      owned_license  = License.create(product: product_1, owner: user)
      user_license_1 = License.create(product: product_2)
      user_license_2 = License.create(product: product_2)

      LicenseUser.create(license: owned_license, user: other_user)
      LicenseUser.create(license: user_license_1, user:)
      LicenseUser.create(license: user_license_2, user:)

      machine_1 = Machine.create(license: user_license_1, owner: user)
      machine_2 = Machine.create(license: user_license_2, owner: user)
      machine_3 = Machine.create(license: owned_license, owner: user)
      machine_4 = Machine.create(license: owned_license, owner: other_user)

      expect(user.products.count).to eq 2
      expect(user.products).to satisfy { _1.to_a in [product_1, product_2] }

      expect(user.machines.count).to eq 4
      expect(user.machines.owned.count).to eq 3
      expect(user.machines).to satisfy { _1.to_a in [machine_1, machine_2, machine_3, machine_4] }
      expect(user.machines.owned).to satisfy { _1.to_a in [machine_1, machine_2, machine_3] }
      expect(user.machines.where.not(id: machine_3)).to satisfy { _1.to_a in [machine_1, machine_2, machine_4] }
      expect(user.machines.where(id: machine_3).count).to eq 1

      expect(other_user.machines.count).to eq 2
      expect(other_user.machines.owned.count).to eq 1
      expect(other_user.machines).to satisfy { _1.to_a in [machine_1, machine_4] }
      expect(other_user.machines.owned).to satisfy { _1.to_a in [machine_4] }

      expect(user.teammates.count).to eq 1
      expect(user.teammates).to satisfy { _1.to_a in [other_user] }

      expect(other_user.teammates.count).to eq 1
      expect(other_user.teammates).to satisfy { _1.to_a in [user] }
    end
  end

  describe 'counting' do
    it 'should support counting a union' do
      user           = User.create
      other_user     = User.create
      owned_license  = License.create(owner: user)
      user_license_1 = License.create
      user_license_2 = License.create

      LicenseUser.create(license: owned_license, user: other_user)
      LicenseUser.create(license: user_license_1, user:)
      LicenseUser.create(license: user_license_2, user:)

      expect(owned_license.users.load.count).to eq(2)
      expect { owned_license.users.count }.to match_queries(count: 1)
    end

    it 'should support sizing a union' do
      user           = User.create
      other_user     = User.create
      owned_license  = License.create(owner: user)
      user_license_1 = License.create
      user_license_2 = License.create

      LicenseUser.create(license: owned_license, user: other_user)
      LicenseUser.create(license: user_license_1, user:)
      LicenseUser.create(license: user_license_2, user:)

      expect(owned_license.users.load.size).to eq(2)
      expect { owned_license.users.size }.to match_queries(count: 0)
    end
  end

  describe 'joining' do
    it 'should support joining a union' do
      user_1 = User.create
      user_2 = User.create
      user_3 = User.create

      license_1 = License.create(owner: user_1)
      license_2 = License.create(owner: user_2)
      license_3 = License.create
      license_4 = License.create
      license_5 = License.create

      LicenseUser.create(license: license_1, user: user_2)
      LicenseUser.create(license: license_3, user: user_1)
      LicenseUser.create(license: license_4, user: user_1)

      expect(User.distinct.joins(:licenses).where(licenses: { id: license_1 }).count).to eq 2
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_2 }).count).to eq 1
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_3 }).count).to eq 1
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_4 }).count).to eq 1
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_5 }).count).to eq 0

      expect(User.distinct.joins(:licenses).where(licenses: { id: license_1 })).to satisfy { _1.to_a in [user_1, user_2] }
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_2 })).to satisfy { _1.to_a in [user_2] }
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_3 })).to satisfy { _1.to_a in [user_1] }
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_4 })).to satisfy { _1.to_a in [user_1] }
      expect(User.distinct.joins(:licenses).where(licenses: { id: license_5 })).to satisfy { _1.to_a in [] }

      expect(License.distinct.joins(:users).where(users: { id: user_1 }).count).to eq 3
      expect(License.distinct.joins(:users).where(users: { id: user_2 }).count).to eq 2
      expect(License.distinct.joins(:users).where(users: { id: user_3 }).count).to eq 0

      expect(License.distinct.joins(:users).where(users: { id: user_1 })).to satisfy { _1.to_a in [license_1, license_3, license_4] }
      expect(License.distinct.joins(:users).where(users: { id: user_2 })).to satisfy { _1.to_a in [license_1, license_2] }
      expect(License.distinct.joins(:users).where(users: { id: user_3 })).to satisfy { _1.to_a in [] }
    end

    it 'should support joining a through union' do
      product_1 = Product.create
      product_2 = Product.create

      user_1 = User.create
      user_2 = User.create
      user_3 = User.create

      license_1 = License.create(product: product_1, owner: user_1)
      license_2 = License.create(product: product_1, owner: user_2)
      license_3 = License.create(product: product_2)
      license_4 = License.create(product: product_2)
      license_5 = License.create(product: product_2)

      LicenseUser.create(license: license_1, user: user_2)
      LicenseUser.create(license: license_3, user: user_1)
      LicenseUser.create(license: license_4, user: user_1)

      machine_1 = Machine.create(license: license_3, owner: user_1)
      machine_2 = Machine.create(license: license_4)
      machine_3 = Machine.create(license: license_1, owner: user_1)
      machine_4 = Machine.create(license: license_1, owner: user_2)
      machine_5 = Machine.create(license: license_2, owner: user_2)
      machine_6 = Machine.create(license: license_5)

      hardware_1 = Hardware.create(machine: machine_1)
      hardware_2 = Hardware.create(machine: machine_4)
      hardware_3 = Hardware.create(machine: machine_4)
      hardware_4 = Hardware.create(machine: machine_4)
      hardware_5 = Hardware.create(machine: machine_5)
      hardware_6 = Hardware.create(machine: machine_5)

      release_1 = Release.create(product: product_1)
      release_2 = Release.create(product: product_1)
      release_3 = Release.create(product: product_1)
      release_4 = Release.create(product: product_2)

      artifact_1 = Artifact.create(release: release_1)
      artifact_2 = Artifact.create(release: release_1)
      artifact_3 = Artifact.create(release: release_2)
      artifact_4 = Artifact.create(release: release_2)
      artifact_5 = Artifact.create(release: release_4)

      expect(User.distinct.joins(:products).where(products: { id: product_1 }).count).to eq 2
      expect(User.distinct.joins(:products).where(products: { id: product_2 }).count).to eq 1

      expect(User.distinct.joins(:products).where(products: { id: product_1 })).to satisfy { _1.to_a in [user_1, user_2] }
      expect(User.distinct.joins(:products).where(products: { id: product_2 })).to satisfy { _1.to_a in [user_1] }

      expect(User.distinct.joins(:machines).where(machines: { id: machine_1 }).count).to eq 1
      expect(User.distinct.joins(:machines).where(machines: { id: machine_2 }).count).to eq 1
      expect(User.distinct.joins(:machines).where(machines: { id: machine_3 }).count).to eq 2
      expect(User.distinct.joins(:machines).where(machines: { id: machine_4 }).count).to eq 2
      expect(User.distinct.joins(:machines).where(machines: { id: machine_5 }).count).to eq 1
      expect(User.distinct.joins(:machines).where(machines: { id: machine_6 }).count).to eq 0

      expect(User.distinct.joins(:machines).where(machines: { id: machine_1 })).to satisfy { _1.to_a in [user_1] }
      expect(User.distinct.joins(:machines).where(machines: { id: machine_2 })).to satisfy { _1.to_a in [user_1] }
      expect(User.distinct.joins(:machines).where(machines: { id: machine_3 })).to satisfy { _1.to_a in [user_1, user_2] }
      expect(User.distinct.joins(:machines).where(machines: { id: machine_4 })).to satisfy { _1.to_a in [user_1, user_2] }
      expect(User.distinct.joins(:machines).where(machines: { id: machine_5 })).to satisfy { _1.to_a in [user_2] }
      expect(User.distinct.joins(:machines).where(machines: { id: machine_6 })).to satisfy { _1.to_a in [] }

      expect(License.distinct.joins(:users).where(users: { id: user_1 }).count).to eq 3
      expect(License.distinct.joins(:users).where(users: { id: user_2 }).count).to eq 2
      expect(License.distinct.joins(:users).where(users: { id: user_3 }).count).to eq 0

      expect(License.distinct.joins(:users).where(users: { id: user_1 })).to satisfy { _1.to_a in [license_1, license_3, license_4] }
      expect(License.distinct.joins(:users).where(users: { id: user_2 })).to satisfy { _1.to_a in [license_1, license_2] }
      expect(License.distinct.joins(:users).where(users: { id: user_3 })).to satisfy { _1.to_a in [] }

      expect(Machine.distinct.joins(license: :users).where(license: { users: { id: user_1 } }).count).to eq 4
      expect(Machine.distinct.joins(license: :users).where(license: { users: { id: user_2 } }).count).to eq 3
      expect(Machine.distinct.joins(license: :users).where(license: { users: { id: user_3 } }).count).to eq 0

      expect(Machine.distinct.joins(license: :users).where(license: { users: { id: user_1 } })).to satisfy { _1.to_a in [machine_1, machine_2, machine_3, machine_4] }
      expect(Machine.distinct.joins(license: :users).where(license: { users: { id: user_2 } })).to satisfy { _1.to_a in [machine_3, machine_4, machine_5] }
      expect(Machine.distinct.joins(license: :users).where(license: { users: { id: user_3 } })).to satisfy { _1.to_a in [] }

      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_1 }).count).to eq 1
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_2 }).count).to eq 0
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_3 }).count).to eq 0
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_4 }).count).to eq 2
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_5 }).count).to eq 1
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_6 }).count).to eq 0

      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_1 })).to satisfy { _1.to_a in [user_1] }
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_2 })).to satisfy { _1.to_a in [] }
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_3 })).to satisfy { _1.to_a in [] }
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_4 })).to satisfy { _1.to_a in [user_1, user_2] }
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_5 })).to satisfy { _1.to_a in [user_2] }
      expect(User.distinct.joins(:hardwares).where(hardwares: { machine_id: machine_6 })).to satisfy { _1.to_a in [] }

      expect(Product.distinct.joins(:users).where(users: { id: user_1 }).count).to eq 2
      expect(Product.distinct.joins(:users).where(users: { id: user_2 }).count).to eq 1
      expect(Product.distinct.joins(:users).where(users: { id: user_3 }).count).to eq 0

      expect(Product.distinct.joins(:users).where(users: { id: user_1 })).to satisfy { _1.to_a in [product_1, product_2] }
      expect(Product.distinct.joins(:users).where(users: { id: user_2 })).to satisfy { _1.to_a in [product_1] }
      expect(Product.distinct.joins(:users).where(users: { id: user_3 })).to satisfy { _1.to_a in [] }

      expect(Release.distinct.joins(product: :users).where(product: { users: { id: user_1 } }).count).to eq 4
      expect(Release.distinct.joins(product: :users).where(product: { users: { id: user_2 } }).count).to eq 3
      expect(Release.distinct.joins(product: :users).where(product: { users: { id: user_3 } }).count).to eq 0

      expect(Release.distinct.joins(product: :users).where(product: { users: { id: user_1 } })).to satisfy { _1.to_a in [release_1, release_2, release_3, release_4] }
      expect(Release.distinct.joins(product: :users).where(product: { users: { id: user_2 } })).to satisfy { _1.to_a in [release_1, release_2, release_3] }
      expect(Release.distinct.joins(product: :users).where(product: { users: { id: user_3 } })).to satisfy { _1.to_a in [] }

      expect(Artifact.distinct.joins(product: :users).where(product: { users: { id: user_1 } }).count).to eq 5
      expect(Artifact.distinct.joins(product: :users).where(product: { users: { id: user_2 } }).count).to eq 4
      expect(Artifact.distinct.joins(product: :users).where(product: { users: { id: user_3 } }).count).to eq 0

      expect(Artifact.distinct.joins(product: :users).where(product: { users: { id: user_1 } })).to satisfy { _1.to_a in [artifact_1, artifact_2, artifact_3, artifact_4, artifact_5] }
      expect(Artifact.distinct.joins(product: :users).where(product: { users: { id: user_2 } })).to satisfy { _1.to_a in [artifact_1, artifact_2, artifact_3, artifact_4] }
      expect(Artifact.distinct.joins(product: :users).where(product: { users: { id: user_3 } })).to satisfy { _1.to_a in [] }
    end
  end

  describe 'preloading' do
    before do
      # user with no licenses
      User.create

      # license with no owner
      license = License.create

      Machine.create(license:)

      # user with owned license
      owner   = User.create(created_at: 1.year.ago)
      license = License.create(owner:, created_at: 1.week.ago)

      Machine.create(license:, owner:)

      # user with user license
      user    = User.create(created_at: 1.minute.ago)
      license = License.create(created_at: 1.month.ago)

      LicenseUser.create(license:, user:, created_at: 2.weeks.ago)
      Machine.create(license:, created_at: 1.week.ago)

      # user with 2 user licenses
      user    = User.create(created_at: 1.week.ago)
      license = License.create(created_at: 1.week.ago)

      LicenseUser.create(license:, user:, created_at: 1.week.ago)
      Machine.create(license:, owner: user, created_at: 1.second.ago)

      license = License.create(created_at: 1.year.ago)

      LicenseUser.create(license:, user:, created_at: 1.year.ago)

      # user with 1 owned and 2 user licenses
      user    = User.create(created_at: 1.week.ago)
      license = License.create(owner:, created_at: 1.week.ago)

      license = License.create(created_at: 1.week.ago)

      LicenseUser.create(license:, user:, created_at: 1.week.ago)
      Machine.create(license:, owner: user, created_at: 1.second.ago)

      license = License.create(created_at: 1.year.ago)

      LicenseUser.create(license:, user:, created_at: 1.year.ago)

      # license with owner and 2 users
      owner   = User.create(created_at: 1.year.ago)
      license = License.create(owner:, created_at: 1.year.ago)

      Machine.create(license:, owner:)

      user = User.create(created_at: 1.week.ago)
      LicenseUser.create(license:, user:, created_at: 1.week.ago)
      Machine.create(license:, owner: user)

      user = User.create(created_at: 1.year.ago)
      LicenseUser.create(license:, user:, created_at: 1.year.ago)
      Machine.create(license:, owner: user)
    end

    it 'should support eager loading a union' do
      licenses = License.eager_load(:users)

      expect(licenses.to_sql).to match_sql <<~SQL.squish
        SELECT
          "licenses"."id" AS t0_r0,
          "licenses"."account_id" AS t0_r1,
          "licenses"."product_id" AS t0_r2,
          "licenses"."owner_id" AS t0_r3,
          "licenses"."last_activity_at" AS t0_r4,
          "licenses"."created_at" AS t0_r5,
          "licenses"."updated_at" AS t0_r6,
          "users"."id" AS t1_r0,
          "users"."account_id" AS t1_r1,
          "users"."email" AS t1_r2,
          "users"."created_at" AS t1_r3,
          "users"."updated_at" AS t1_r4
        FROM
          "licenses"
          LEFT OUTER JOIN "license_users" ON "license_users"."license_id" = "licenses"."id"
          LEFT OUTER JOIN "users" ON (
            "users"."id" = "licenses"."owner_id"
            OR "users"."id" = "license_users"."user_id"
          )
      SQL

      licenses.each do |license|
        expect(license.association(:users).loaded?).to be true
        expect(license.association(:owner).loaded?).to be false
        expect(license.association(:licensees).loaded?).to be false

        expect { license.users }.to match_queries(count: 0)
        expect(license.users.sort_by(&:id)).to eq license.reload.users.sort_by(&:id)
      end
    end

    it 'should support eager loading a through union' do
      users = User.eager_load(:machines)

      expect(users.to_sql).to match_sql <<~SQL.squish
        SELECT
          "users"."id" AS t0_r0,
          "users"."account_id" AS t0_r1,
          "users"."email" AS t0_r2,
          "users"."created_at" AS t0_r3,
          "users"."updated_at" AS t0_r4,
          "machines"."id" AS t1_r0,
          "machines"."account_id" AS t1_r1,
          "machines"."license_id" AS t1_r2,
          "machines"."owner_id" AS t1_r3,
          "machines"."created_at" AS t1_r4,
          "machines"."updated_at" AS t1_r5
        FROM
          "users"
          LEFT OUTER JOIN "license_users" ON "license_users"."user_id" = "users"."id"
          LEFT OUTER JOIN "licenses" ON (
            "licenses"."owner_id" = "users"."id"
            OR "licenses"."id" = "license_users"."license_id"
          )
          LEFT OUTER JOIN "machines" ON "machines"."license_id" = "licenses"."id"
      SQL

      users.each do |user|
        expect(user.association(:machines).loaded?).to be true
        expect(user.association(:licenses).loaded?).to be false

        expect { user.machines }.to match_queries(count: 0)
        expect(user.machines.sort_by(&:id)).to eq user.reload.machines.sort_by(&:id)
      end
    end

    it 'should support preloading a union', :unprepared_statements do
      licenses = License.preload(:users)

      expect { licenses }.to(
        match_queries(count: 4) do |queries|
          license_ids = licenses.ids.uniq
          owner_ids   = licenses.map(&:owner_id).compact.uniq
          user_ids    = licenses.flat_map(&:licensee_ids).uniq

          expect(queries.first).to match_sql <<~SQL.squish
            SELECT "licenses".* FROM "licenses"
          SQL

          expect(queries.second).to match_sql <<~SQL.squish
            SELECT
              "users".*
            FROM
              "users"
            WHERE
              "users"."id" IN (
                #{owner_ids.join(', ')}
              )
          SQL

          expect(queries.third).to match_sql <<~SQL.squish
            SELECT
              "license_users".*
            FROM
              "license_users"
            WHERE
              "license_users"."license_id" IN (
                #{license_ids.join(', ')}
              )
          SQL

          expect(queries.fourth).to match_sql <<~SQL.squish
            SELECT
              "users".*
            FROM
              "users"
            WHERE
              "users"."id" IN (
                #{user_ids.join(', ')}
              )
          SQL
        end
      )

      licenses.each do |license|
        expect(license.association(:users).loaded?).to be true
        expect(license.association(:owner).loaded?).to be true
        expect(license.association(:licensees).loaded?).to be true

        expect { license.users }.to match_queries(count: 0)
        expect(license.users.sort_by(&:id)).to eq license.reload.users.sort_by(&:id)
      end
    end

    it 'should support preloading a through union', :unprepared_statements do
      users = User.preload(:machines)

      expect { users }.to(
        match_queries(count: 5) do |queries|
          user_ids           = users.ids.uniq
          shared_license_ids = users.flat_map(&:shared_license_ids).reverse.uniq.reverse # order is significant
          owned_license_ids  = users.flat_map(&:license_ids).uniq

          expect(queries.first).to match_sql <<~SQL.squish
            SELECT "users".* FROM "users"
          SQL

          expect(queries.second).to match_sql <<~SQL.squish
            SELECT
              "licenses".*
            FROM
              "licenses"
            WHERE
              "licenses"."owner_id" IN (
                #{user_ids.join(', ')}
              )
          SQL

          expect(queries.third).to match_sql <<~SQL.squish
            SELECT
              "license_users".*
            FROM
              "license_users"
            WHERE
              "license_users"."user_id" IN (
                #{user_ids.join(', ')}
              )
          SQL

          expect(queries.fourth).to match_sql <<~SQL.squish
            SELECT
              "licenses".*
            FROM
              "licenses"
            WHERE
              "licenses"."id" IN (
                #{shared_license_ids.join(', ')}
              )
          SQL

          expect(queries.fifth).to match_sql <<~SQL.squish
            SELECT
              DISTINCT "machines".*
            FROM
              "machines"
            WHERE
              "machines"."license_id" IN (
                #{owned_license_ids.join(', ')}
              )
          SQL
        end
      )

      users.each do |user|
        expect(user.association(:machines).loaded?).to be true
        expect(user.association(:licenses).loaded?).to be true

        expect { user.machines }.to match_queries(count: 0)
        expect(user.machines.sort_by(&:id)).to eq user.reload.machines.sort_by(&:id)
      end
    end
  end

  describe UnionOf::Macro do
    temporary_model :model, table_name: :users do
      has_many :owned_licenses, foreign_key: :user_id
      has_many :license_users, foreign_key: :user_id
      has_many :user_licenses, through: :license_users
    end

    subject { Model }

    describe '.union_of' do
      it 'should respond' do
        expect(subject.respond_to?(:union_of)).to be true
      end

      it 'should not raise' do
        expect { subject.union_of :licenses, sources: %i[owned_licenses user_licenses] }.to_not raise_error
      end

      it 'should define' do
        subject.union_of :licenses, sources: %i[owned_licenses user_licenses]

        expect(subject.reflect_on_association(:licenses)).to_not be nil
        expect(subject.reflect_on_association(:licenses).macro).to eq :union_of
        expect(subject.reflect_on_union(:licenses)).to_not be nil
        expect(subject.reflect_on_union(:licenses).macro).to eq :union_of
      end
    end

    describe '.has_many' do
      it 'should respond' do
        expect(subject.respond_to?(:has_many)).to be true
      end

      it 'should not raise' do
        expect { subject.has_many :licenses, union_of: %i[owned_licenses user_licenses] }.to_not raise_error
      end

      it 'should define' do
        subject.has_many :licenses, union_of: %i[owned_licenses user_licenses]

        expect(subject.reflect_on_association(:licenses)).to_not be nil
        expect(subject.reflect_on_association(:licenses).macro).to eq :union_of
        expect(subject.reflect_on_union(:licenses)).to_not be nil
        expect(subject.reflect_on_union(:licenses).macro).to eq :union_of
      end
    end
  end

  describe UnionOf::ReadonlyAssociation do
    subject { User.create }

    it 'should not raise on readers' do
      expect { subject.licenses }.to_not raise_error
      expect { subject.licenses.first }.to_not raise_error
      expect { subject.licenses.last }.to_not raise_error
      expect { subject.licenses.forty_two }.to_not raise_error
      expect { subject.licenses.take }.to_not raise_error
    end

    it 'should not raise on query methods' do
      expect { subject.licenses.find_by(id: SecureRandom.uuid) }.to_not raise_error
      expect { subject.licenses.where(name: 'Foo') }.to_not raise_error
    end

    it 'should not raise on ID readers' do
      expect { subject.licenses.ids }.to_not raise_error
      expect { subject.license_ids }.to_not raise_error
    end

    it 'should raise on IDs writer' do
      expect { subject.license_ids = [] }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on build' do
      expect { subject.licenses.build(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.new(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on create' do
      expect { subject.licenses.create(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.create(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on insert' do
      expect { subject.licenses.insert!(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.insert(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.insert_all!([]) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.insert_all([]) }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on upsert' do
      expect { subject.licenses.upsert(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.upsert_all([]) }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on update' do
      expect { subject.licenses.update_all(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.update!(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.update(id: SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on delete' do
      expect { subject.licenses.delete_all }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.delete(SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
    end

    it 'should raise on destroy' do
      expect { subject.licenses.destroy_all }.to raise_error UnionOf::ReadonlyAssociationError
      expect { subject.licenses.destroy(SecureRandom.uuid) }.to raise_error UnionOf::ReadonlyAssociationError
    end
  end

  # TODO(ezekg) Add exhaustive tests for all association macros, e.g.
  #             belongs_to, has_many, etc.

  describe 'README' do
    temporary_table :users, force: true do |t|
      t.string :name
    end

    temporary_table :books do |t|
      t.integer :author_id
      t.string :title
    end

    temporary_table :coauthorships do |t|
      t.integer :book_id
      t.integer :user_id
    end

    temporary_table :edits do |t|
      t.integer :book_id
      t.integer :user_id
    end

    temporary_table :illustrations do |t|
      t.integer :book_id
      t.integer :user_id
    end

    temporary_table :forewords do |t|
      t.integer :book_id
      t.integer :user_id
    end

    temporary_table :prefaces do |t|
      t.integer :book_id
      t.integer :user_id
    end

    temporary_model :user do
      has_many :books
      has_many :coauthorships
      has_many :edits
      has_many :illustrations
      has_many :forewords
    end

    temporary_model :coauthorship do
      belongs_to :book
      belongs_to :user
    end

    temporary_model :edit do
      belongs_to :book
      belongs_to :user
    end

    temporary_model :illustration do
      belongs_to :book
      belongs_to :user
    end

    temporary_model :foreword do
      belongs_to :book
      belongs_to :user
    end

    temporary_model :preface do
      belongs_to :book
      belongs_to :user
    end

    temporary_model :book do
      belongs_to :author, class_name: 'User', foreign_key: 'author_id', optional: true

      has_many :coauthorships
      has_many :coauthors, through: :coauthorships, source: :user

      has_many :prefaces
      has_many :prefacers, through: :prefaces, source: :user

      has_many :forewords
      has_many :foreworders, through: :forewords, source: :user

      has_many :illustrations
      has_many :illustrators, through: :illustrations, source: :user

      has_many :edits
      has_many :editors, through: :edits, source: :user

      has_many :contributors, -> { distinct }, class_name: 'User', union_of: %i[
        author
        coauthors
        foreworders
        prefacers
        illustrators
        editors
      ]
    end

    let(:author) { User.create(name: 'Isaac Asimov') }
    let(:editor) { User.create(name: 'John W. Campbell') }
    let(:illustrator) { User.create(name: 'Frank Kelly Freas') }
    let(:writer) { User.create(name: 'Ray Bradbury') }
    let(:book) {
      book = Book.create(title: 'I, Robot', author:)

      Preface.create(user: author, book:)
      Foreword.create(user: writer, book:)
      Foreword.create(user: editor, book:)
      Illustration.create(user: illustrator, book:)
      Edit.create(user: editor, book:)

      book
    }

    it 'should return contributors' do
      expect(book.contributors).to satisfy { _1.to_a in [author, editor, illustrator, writer] }
    end

    it 'should use limit' do
      expect(book.contributors.order(:name).limit(3)).to satisfy { _1.to_a in [author, editor, illustrator] }
    end

    it 'should use predicate' do
      expect(book.contributors.where(id: editor.id)).to satisfy { _1.to_a in [editor] }
    end

    it 'should use UNION' do
      expect(book.contributors.to_sql).to match_sql <<~SQL.squish
        SELECT
          DISTINCT users.*
        FROM
          users
        WHERE
          users.id IN (
            SELECT
              users.id
            FROM
              (
                (
                  SELECT
                    users.id
                  FROM
                    users
                  WHERE
                    users.id = 1
                  LIMIT
                    1
                )
                UNION
                (
                  SELECT
                    users.id
                  FROM
                    users INNER JOIN coauthorships ON users.id = coauthorships.user_id
                  WHERE
                    coauthorships.book_id = 1
                )
                UNION
                (
                  SELECT
                    users.id
                  FROM
                    users INNER JOIN forewords ON users.id = forewords.user_id
                  WHERE
                    forewords.book_id = 1
                )
                UNION
                (
                  SELECT
                    users.id
                  FROM
                    users INNER JOIN prefaces ON users.id = prefaces.user_id
                  WHERE
                    prefaces.book_id = 1
                )
                UNION
                (
                  SELECT
                    users.id
                  FROM
                    users INNER JOIN illustrations ON users.id = illustrations.user_id
                  WHERE
                    illustrations.book_id = 1
                )
                UNION
                (
                  SELECT
                    users.id
                  FROM
                    users INNER JOIN edits ON users.id = edits.user_id
                  WHERE
                    edits.book_id = 1
                )
              ) users
          )
      SQL
    end

    it 'should support joins' do
      expect { Book.joins(:contributors).where(contributors: { user_id: author.id }) }.to_not raise_error
    end

    it 'should support preloading' do
      expect { Book.preload(:contributors) }.to_not raise_error
    end

    it 'should support eager loading' do
      expect { Book.eager_load(:contributors) }.to_not raise_error
    end

    it 'should support includes' do
      expect { Book.includes(:contributors) }.to_not raise_error
    end
  end
end
