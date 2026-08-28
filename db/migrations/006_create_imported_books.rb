# frozen_string_literal: true

# Persist books imported from a Goodreads CSV export.
#
# Shelves have lived in the session cache, which means they vanish with the
# session and every view of them costs another call to the Goodreads API that
# Amazon deprecated in December 2020. Storing an upload makes a library durable
# and removes the API from the read path entirely.
Sequel.migration do
  change do
    create_table :imported_books do
      primary_key :id
      foreign_key :user_id, :accounts, null: false, on_delete: :cascade

      # Goodreads 'Book Id' when the export carries it. Not relied on for
      # uniqueness because a hand-trimmed CSV can omit the column.
      String :goodreads_book_id
      # goodreads_book_id, or "title|author" when that column is absent.
      String :dedupe_key, null: false

      String :isbn
      String :title, null: false
      String :author
      String :published_year
      # 0 means unrated and must stay excluded from shelf averages.
      Integer :rating, null: false, default: 0
      # ISO YYYY-MM-DD so it sorts lexicographically. See #439.
      String :date_added
      String :exclusive_shelf
      # JSON array. A book can sit on many shelves at once.
      String :shelves, null: false, default: '[]'

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index %i[user_id dedupe_key], unique: true, name: :imported_books_unique
      index :user_id, name: :imported_books_user_id
    end
  end
end
