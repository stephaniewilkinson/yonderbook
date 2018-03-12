# frozen_string_literal: true

require_relative '../lib/db'

DB.create_table(:books) do
  primary_key :id
  foreign_key :user_id, :users, null: false

  String :isbn, null: false
  String :title
  String :cover_image_url
end
