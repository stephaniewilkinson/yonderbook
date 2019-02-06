# frozen_string_literal: true

require_relative '../lib/db'

DB.migration do
  up do
    add_column :access_token, String
    add_column :access_token_secret, String
    from(:users)
  end

  down do
    drop_column :users, :access_token
    drop_column :users, :access_token_secret
  end
end
