# frozen_string_literal: true

# Availability alerts, part 2 (#1422): "your library added it".
#
# Watched titles (007) are copies a library already owns. A book none of the
# reader's libraries had is kept here instead, by title, author and ISBN, and
# searched for again once a week. When a library turns out to have it, it
# moves to watched_titles.
Sequel.migration do
  change do
    create_table :wanted_books do
      primary_key :id
      foreign_key :user_id, :accounts, null: false, on_delete: :cascade
      String :title, null: false
      String :author
      String :isbn
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :user_id
    end

    # When the weekly search last ran for this subscription.
    alter_table(:alert_subscriptions) { add_column :last_searched_at, DateTime }
  end
end
