require_relative "../db.rb"

DB.create_table(:users) do
  primary_key :id
  String :email, uniq: true, null: false
  Integer :goodreads_user_id
end
