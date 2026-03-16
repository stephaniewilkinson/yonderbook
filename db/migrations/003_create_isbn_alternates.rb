# frozen_string_literal: true

Sequel.migration do
  change do
    create_table :isbn_alternates do
      String :isbn, primary_key: true
      String :alternate_isbns # JSON array
      String :work_key
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
