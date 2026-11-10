# frozen_string_literal: true

# Availability alerts (#1422): email a reader when a book on their list that
# their library owns, but had no copy free, comes free.
#
# A full availability check searches OverDrive by title, one request per book
# per library. Storing the OverDrive product (reserve) id of every copy a
# reader was shown lets the daily re-check skip the search and ask only for
# availability, 25 products per request.
Sequel.migration do
  change do
    create_table :alert_subscriptions do
      primary_key :id
      # One subscription per account: turning alerts on again replaces it.
      foreign_key :user_id, :accounts, null: false, unique: true, on_delete: :cascade
      # [[consortium_id, library_name], ...] as the reader picked them.
      String :libraries, null: false, default: '[]'
      String :shelf_name
      # Put in every email's unsubscribe link, so one click needs no login.
      String :unsubscribe_token, null: false, unique: true
      TrueClass :enabled, null: false, default: true
      DateTime :last_checked_at
      DateTime :last_emailed_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table :watched_titles do
      primary_key :id
      foreign_key :user_id, :accounts, null: false, on_delete: :cascade
      String :consortium_id, null: false
      # OverDrive's product id for this format at this library.
      String :reserve_id, null: false
      String :title, null: false
      String :author
      String :format
      String :library_name
      String :url
      Integer :copies_available, null: false, default: 0
      Integer :copies_owned, null: false, default: 0
      DateTime :last_checked_at
      # When the reader was last emailed about this copy being free.
      DateTime :notified_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      unique %i[user_id consortium_id reserve_id]
      index :user_id
    end
  end
end
