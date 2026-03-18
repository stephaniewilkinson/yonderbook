# frozen_string_literal: true

# Tracks ISBNs sent to BookMooch per user to avoid duplicate wishlist adds
class BookmoochImport < Sequel::Model
  many_to_one :account, key: :user_id

  def self.already_imported_isbns user_id
    where(user_id: user_id).select_map(:isbn).to_set
  end

  def self.record_imports user_id, books_added, shelf_name: nil
    db.transaction do
      books_added.each do |book|
        next if book[:isbn].nil? || book[:isbn].empty?

        dataset.insert_conflict(
          target: %i[user_id isbn],
          update: {last_seen_at: Sequel::CURRENT_TIMESTAMP, shelf_name: shelf_name}
        ).insert(
          user_id: user_id,
          isbn: book[:isbn],
          bookmooch_isbn: book[:bookmooch_isbn],
          shelf_name: shelf_name,
          last_seen_at: Sequel::CURRENT_TIMESTAMP
        )
      end
    end
  end

  def self.clear_imports user_id
    where(user_id: user_id).delete
  end
end
