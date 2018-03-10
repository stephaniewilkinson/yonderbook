require_relative "../db.rb"

DB.create_table(:books) do
  primary_key :id
  foreign_key :artist_id, :artists, null: false

  String :isbn, uniq: true, null: false
  String :title
  String :cover_image_url
  String :barcode_image_url
end
