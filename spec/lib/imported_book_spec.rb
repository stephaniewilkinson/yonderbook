# frozen_string_literal: true

require_relative 'spec_helper'
require 'database'

Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

require 'models/account'
require 'models/imported_book'

describe ImportedBook do
  before do
    DB.run('PRAGMA foreign_keys = OFF')
    DB.tables.each { |t| DB[t].delete }
    DB.run('PRAGMA foreign_keys = ON')
    @account = Account.create(email: "test_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
  end

  def book overrides = {}
    {
      goodreads_book_id: '25489134',
      isbn: '9780446675505',
      title: 'Parable of the Sower',
      author: 'Octavia E. Butler',
      published_year: '2000',
      ratings: 5,
      date_added: '2019-11-02',
      exclusive_shelf: 'to-read',
      shelves: %w[to-read sci-fi]
    }.merge(overrides)
  end

  def titles books
    books.map { |stored| stored[:title] }
  end

  describe '.replace_library' do
    it 'stores the books and returns how many were kept' do
      books = [book, book(goodreads_book_id: '2', title: 'Piranesi')]

      assert_equal 2, ImportedBook.replace_library(@account.id, books)
    end

    it 'replaces the previous import rather than merging into it' do
      ImportedBook.replace_library @account.id, [book, book(goodreads_book_id: '2', title: 'Piranesi')]
      ImportedBook.replace_library @account.id, [book]

      assert_equal ['Parable of the Sower'], titles(ImportedBook.library(@account.id))
    end

    it 'drops duplicate rows within a single import instead of raising' do
      assert_equal 1, ImportedBook.replace_library(@account.id, [book, book])
    end

    it 'falls back to title and author when the export has no Book Id' do
      books = [book(goodreads_book_id: nil), book(goodreads_book_id: nil, title: 'Other')]

      assert_equal 2, ImportedBook.replace_library(@account.id, books)
    end

    it 'leaves another account library untouched' do
      other = Account.create(email: "other_#{rand(1_000_000)}@example.com", password_hash: 'hash', status_id: 2)
      ImportedBook.replace_library other.id, [book]
      ImportedBook.replace_library @account.id, []

      assert_equal 1, ImportedBook.library(other.id).length
    end

    it 'stores an empty library without raising' do
      assert_equal 0, ImportedBook.replace_library(@account.id, [])
    end

    # A truncated or unreadable upload must not destroy real data.
    it 'does not wipe an existing library when the import yields nothing' do
      ImportedBook.replace_library @account.id, [book]
      ImportedBook.replace_library @account.id, []

      assert_equal 1, ImportedBook.library(@account.id).length
    end

    it 'raises once the import passes max' do
      two = [book(goodreads_book_id: '1'), book(goodreads_book_id: '2')]

      assert_raises(ImportedBook::TooManyBooks) { ImportedBook.replace_library(@account.id, two, max: 1) }
    end

    it 'leaves the previous library intact after a too-large import' do
      ImportedBook.replace_library @account.id, [book]
      two = [book(goodreads_book_id: '1'), book(goodreads_book_id: '2')]
      begin
        ImportedBook.replace_library @account.id, two, max: 1
      rescue ImportedBook::TooManyBooks
        nil
      end

      assert_equal 1, ImportedBook.library(@account.id).length
    end

    it 'accepts a lazy enumerator, not just an array' do
      assert_equal 1, ImportedBook.replace_library(@account.id, [book].each)
    end

    it 'dedupes across insert batches, not just within one' do
      many = Array.new(ImportedBook::BATCH_SIZE + 10) { book }

      assert_equal 1, ImportedBook.replace_library(@account.id, many)
    end
  end

  describe '.library' do
    it 'returns the hash shape the rest of the app reads' do
      ImportedBook.replace_library @account.id, [book]
      stored = ImportedBook.library(@account.id).first

      assert_equal '9780446675505', stored[:isbn]
      assert_equal 5, stored[:ratings]
      assert_equal %w[to-read sci-fi], stored[:shelves]
    end

    it 'leaves image_url nil because a CSV export carries no cover URLs' do
      ImportedBook.replace_library @account.id, [book]

      assert_nil ImportedBook.library(@account.id).first[:image_url]
    end

    it 'orders by date added, newest first' do
      books = [book(goodreads_book_id: '1', title: 'Older', date_added: '2015-01-01'), book(goodreads_book_id: '2', title: 'Newer', date_added: '2024-06-01')]
      ImportedBook.replace_library @account.id, books

      assert_equal %w[Newer Older], titles(ImportedBook.library(@account.id))
    end

    it 'puts books with no date added last' do
      books = [book(goodreads_book_id: '1', title: 'Undated', date_added: nil), book(goodreads_book_id: '2', title: 'Dated', date_added: '2015-01-01')]
      ImportedBook.replace_library @account.id, books

      assert_equal %w[Dated Undated], titles(ImportedBook.library(@account.id))
    end

    it 'survives a malformed shelves column' do
      ImportedBook.replace_library @account.id, [book]
      ImportedBook.where(user_id: @account.id).update(shelves: 'not json')

      assert_empty ImportedBook.library(@account.id).first[:shelves]
    end
  end

  describe '.shelf_counts' do
    it 'counts books per shelf, largest first' do
      ImportedBook.replace_library @account.id, [book, book(goodreads_book_id: '2', title: 'Piranesi', shelves: %w[read])]

      assert_equal [['read', 1], ['sci-fi', 1], ['to-read', 1]], ImportedBook.shelf_counts(@account.id)
    end

    it 'orders by count before name' do
      books = [book(shelves: %w[small big]), book(goodreads_book_id: '2', shelves: %w[big])]
      ImportedBook.replace_library @account.id, books

      assert_equal [['big', 2], ['small', 1]], ImportedBook.shelf_counts(@account.id)
    end
  end

  describe '.books_on' do
    it 'returns only the books carrying that shelf' do
      ImportedBook.replace_library @account.id, [book, book(goodreads_book_id: '2', title: 'Piranesi', shelves: %w[read])]

      assert_equal %w[Piranesi], titles(ImportedBook.books_on(@account.id, 'read'))
    end

    it 'returns nothing for an unknown shelf' do
      ImportedBook.replace_library @account.id, [book]

      assert_empty ImportedBook.books_on(@account.id, 'nope')
    end
  end

  describe '.imported? and .clear' do
    it 'reports whether the account has an imported library' do
      refute ImportedBook.imported?(@account.id)
      ImportedBook.replace_library @account.id, [book]

      assert ImportedBook.imported?(@account.id)
    end

    it 'removes the library' do
      ImportedBook.replace_library @account.id, [book]
      ImportedBook.clear @account.id

      refute ImportedBook.imported?(@account.id)
    end
  end

  it 'deletes the library when the account goes away' do
    ImportedBook.replace_library @account.id, [book]
    @account.destroy

    assert_empty ImportedBook.library(@account.id)
  end
end
