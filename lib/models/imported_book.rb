# frozen_string_literal: true

require 'json'

# Books imported from a Goodreads CSV export, stored per account so a library
# outlives the session and can be read back without the deprecated Goodreads API.
#
# Reads return the same hash shape Goodreads.get_books produces, so OverDrive
# availability and BookMooch consume an imported shelf unchanged.
class ImportedBook < Sequel::Model
  many_to_one :account, key: :user_id

  COLUMNS = %i[user_id dedupe_key goodreads_book_id isbn title author published_year rating date_added exclusive_shelf shelves].freeze

  # An import is the whole library, so it replaces the previous one rather than
  # merging -- otherwise books removed on Goodreads would linger forever.
  # Returns the number of books stored.
  def self.replace_library user_id, books
    rows = books.map { |book| values_for user_id, book }.uniq { |row| row[1] }
    db.transaction do
      where(user_id: user_id).delete
      import COLUMNS, rows unless rows.empty?
    end
    rows.length
  end

  def self.values_for user_id, book
    [
      user_id,
      dedupe_key(book),
      book[:goodreads_book_id],
      book[:isbn],
      book[:title],
      book[:author],
      book[:published_year],
      book[:ratings].to_i,
      book[:date_added],
      book[:exclusive_shelf],
      JSON.generate(book[:shelves] || [])
    ]
  end

  def self.dedupe_key book
    book[:goodreads_book_id] || "#{book[:title]}|#{book[:author]}"
  end

  # Newest addition first. date_added is stored ISO so this orders correctly in
  # SQL; NULLs land at the end.
  def self.library user_id
    where(user_id: user_id).order(Sequel.desc(:date_added), Sequel.asc(:id)).map(&:to_book)
  end

  def self.books_on user_id, shelf_name
    library(user_id).select { |book| book[:shelves].include? shelf_name }
  end

  # [[shelf_name, book_count], ...], largest shelf first, ties broken by name.
  def self.shelf_counts user_id
    counts = Hash.new 0
    where(user_id: user_id).select_map(:shelves).each do |json|
      parse_shelves(json).each { |shelf| counts[shelf] += 1 }
    end
    counts.sort_by { |name, count| [-count, name] }
  end

  def self.imported? user_id
    where(user_id: user_id).any?
  end

  def self.clear user_id
    where(user_id: user_id).delete
  end

  # A malformed shelves column must not take down a whole library read.
  def self.parse_shelves json
    parsed = JSON.parse json.to_s
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def to_book
    {
      isbn:,
      image_url: nil,
      title:,
      author:,
      published_year:,
      ratings: rating,
      date_added:,
      goodreads_book_id:,
      exclusive_shelf:,
      shelves: shelf_list
    }
  end

  def shelf_list
    self.class.parse_shelves shelves
  end
end
