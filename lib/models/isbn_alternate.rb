# frozen_string_literal: true

require 'json'

# IsbnAlternate model for caching Open Library ISBN alternate lookups
class IsbnAlternate < Sequel::Model(:isbn_alternates)
  STALE_AFTER_DAYS = 30

  def self.bulk_lookup isbns
    fresh_cutoff = Time.now - (STALE_AFTER_DAYS * 86_400)
    where(isbn: isbns).where { created_at > fresh_cutoff }
      .to_h { |row| [row.isbn, row.alternate_isbns_array] }
  end

  def self.store isbn, alternates, work_key: nil
    json = JSON.generate(alternates)
    dataset.insert_conflict(target: :isbn, update: {alternate_isbns: json, work_key: work_key, created_at: Sequel::CURRENT_TIMESTAMP})
      .insert(isbn: isbn, alternate_isbns: json, work_key: work_key)
  end

  def alternate_isbns_array
    JSON.parse(alternate_isbns || '[]')
  end
end
