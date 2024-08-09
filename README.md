# union_of

[![CI](https://github.com/keygen-sh/union_of/actions/workflows/test.yml/badge.svg)](https://github.com/keygen-sh/union_of/actions)
[![Gem Version](https://badge.fury.io/rb/union_of.svg)](https://badge.fury.io/rb/union_of)

Use `union_of` to create unions of other associations in Active Record, using a
SQL `UNION` under the hood. `union_of` has full support for joins, preloading,
and eager loading of union associations.

This gem was extracted from [Keygen](https://keygen.sh) and is being used in
production to serve millions of API requests per day.

Sponsored by:

<a href="https://keygen.sh?ref=union_of">
  <div>
    <img src="https://keygen.sh/images/logo-pill.png" width="200" alt="Keygen">
  </div>
</a>

_A fair source software licensing and distribution API._

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem 'union_of'
```

And then execute:

```bash
$ bundle
```

Or install it yourself as:

```bash
$ gem install union_of
```

## Usage

To use `union_of`, create a `has_many` association as you would normally, and
define the associations you'd like to union together via `union_of:`:

```ruby
class User < ActiveRecord::Base
  has_many :owned_licenses
  has_many :license_users
  has_many :shared_licenses, through: :license_users, source: :license

  # create a union of the user's owned licenses and shared licenses
  has_many :licenses, union_of: %i[
    owned_licenses
    shared_licenses
  ]
end
```

Here's a quick example of what's possible:

```ruby
user           = User.create
owned_license  = License.create(owner: user)

3.times do
  shared_license = License.create
  license_user   = LicenseUser.create(license: shared_license, user:)
end

user.licenses.to_a                # => [#<License id=1>, #<License id=2>, #<License id=3>, #<License id=4>]
user.licenses.order(:id).limit(1) # => [#<License id=4>]
user.licenses.where(id: 2)        # => [#<License id=2>]
user.licenses.to_sql
# => SELECT * FROM licenses WHERE id IN (
#      SELECT id FROM licenses WHERE owner_id = ?
#      UNION
#      SELECT licenses.id FROM licenses INNER JOIN license_users ON licenses.id = license_users.license_id WHERE license_users.user_id = ?
#    )

User.joins(:licenses).where(licenses: { ... })
User.preload(:licenses)
User.eager_load(:licenses)
User.includes(:licenses)
```

There is support for complex unions as well, e.g. a union made up of direct and
through associations, or even other union associations.

## Supported databases

We currently support PostgreSQL, MySQL, and MariaDB. We'd love contributions
that add SQLite support, but we probably won't add it ourselves.

## Supported Rubies

**`union_of` supports Ruby 3.1 and above.** We encourage you to upgrade if
you're on an older version. Ruby 3 provides a lot of great features, like better
pattern matching and a new shorthand hash syntax.

## Performance notes

As is expected, you will need to pay close attention to performance and ensure
your tables are indexed well. We have tried to make the underlying `UNION`
queries as efficient as possible, but please open an issue or PR if you are
encountering a performance issue that is caused by this gem.

We use Postgres in production, but we do not actively use MySQL or MariaDB, so
there may be performance issues we are unaware of. If you stumble upon issues,
please open an issue or a PR.

## Is it any good?

Yes.

## Contributing

If you have an idea, or have discovered a bug, please open an issue or create a
pull request.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
