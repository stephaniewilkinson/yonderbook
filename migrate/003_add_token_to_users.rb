# frozen_string_literal: true

require_relative '../lib/db'

DB.alter_table(:users) do
  add_column :access_token, String
  add_column :access_token_secret, String
end
