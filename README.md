# union_of

[![CI](https://github.com/keygen-sh/union_of/actions/workflows/test.yml/badge.svg)](https://github.com/keygen-sh/union_of/actions)
[![Gem Version](https://badge.fury.io/rb/union_of.svg)](https://badge.fury.io/rb/union_of)

Use `union_of` to create associations that combine multiple Active Record
associations using a SQL `UNION` under the hood. `union_of` fully supports
joins, preloading, and eager loading, as well as through-union associations.

This gem was extracted from [Keygen](https://keygen.sh) and is being used in
production to serve millions of API requests per day, performantly querying
tables with millions and millions of rows.

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
class Book < ActiveRecord::Base
  # the primary author of the book
  belongs_to :author, class_name: 'User', foreign_key: 'author_id', optional: true

  # coauthors of the book via a join table
  has_many :coauthorships
  has_many :coauthors, through: :coauthorships, source: :user

  # prefacers for the book via a join table
  has_many :prefaces
  has_many :prefacers, through: :prefaces, source: :user

  # prefacers for the book via a join table
  has_many :forewords
  has_many :foreworders, through: :forewords, source: :user

  # illustrators for the book via a join table
  has_many :illustrations
  has_many :illustrators, through: :illustrations, source: :user

  # editors for the book via a join table
  has_many :edits
  has_many :editors, through: :edits, source: :user

  # union association for all contributors to the book
  has_many :contributors, -> { distinct }, class_name: 'User', union_of: %i[
    author
    coauthors
    foreworders
    prefacers
    illustrators
    editors
  ]
end
```

Here's a quick example of what's possible:

```ruby
# contributors to the book
author = User.create(name: 'Isaac Asimov')
editor = User.create(name: 'John W. Campbell')
illustrator = User.create(name: 'Frank Kelly Freas')
writer = User.create(name: 'Ray Bradbury')

# create book by the author
book = Book.create(title: 'I, Robot', author:)

# assign a preface by the author
Preface.create(user: author, book:)

# assign foreword writers
Foreword.create(user: writer, book:)
Foreword.create(user: editor, book:)

# assign an illustrator
Illustration.create(user: illustrator, book:)

# assign an editor
Edit.create(user: editor, book:)

# access all contributors (author, editors, illustrator, etc.)
book.contributors.to_a
# => [#<User id=1, name="Isaac Asimov">, #<User id=2, name="John W. Campbell">, #<User id=3, name="Frank Kelly Freas">, #<User id=4, name="Ray Bradbury">]

# example of querying the union of contributors
book.contributors.order(:name).limit(3)
# => [#<User id=4, name="Frank Kelly Freas">, #<User id=3, name="Isaac Asimov">, #<User id=2, name="John W. Campbell">]

book.contributors.where(id: editor.id)
# => [#<User id=2, name="John W. Campbell">]

book.contributors.to_sql
# => SELECT * FROM users WHERE id IN (
#      SELECT id FROM users WHERE id = 1
#      UNION
#      SELECT users.id FROM users INNER JOIN prefaces ON users.id = prefaces.user_id WHERE prefaces.book_id = 1
#      UNION
#      SELECT users.id FROM users INNER JOIN forewords ON users.id = forewords.user_id WHERE forewords.book_id = 1
#      UNION
#      SELECT users.id FROM users INNER JOIN illustrations ON users.id = illustrations.user_id WHERE illustrations.book_id = 1
#      UNION
#      SELECT users.id FROM users INNER JOIN edits ON users.id = edits.user_id WHERE edits.book_id = 1
#   )

# example of more advanced querying e.g. preloading the union
Book.joins(:contributors).where(contributors: { ... })
Book.preload(:contributors)
Book.eager_load(:contributors)
Book.includes(:contributors)
```

Right now, the underlying table and model for each unioned association must
match. We'd like to change that in the future. Originally, `union_of` was
defined to make migrating from a has-one relationship to a many-to-many
relationship easier and safer, while retaining backwards compatibility.

There is support for complex unions as well, e.g. a union made up of direct and
through associations, even when those associations utilize union associations.

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
encountering a performance issue that is caused by this gem. But good indexing
will go a long way.

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
