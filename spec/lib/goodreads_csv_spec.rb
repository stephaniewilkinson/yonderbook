# frozen_string_literal: true

require_relative 'spec_helper'
require 'goodreads_csv'

describe GoodreadsCsv do
  def headers
    'Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,' \
      'Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,' \
      'Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Owned Copies'
  end

  def sower
    '25489134,"Parable of the Sower (Earthseed, #1)",Octavia E. Butler,"Butler, Octavia E.",,"=""0446675504""",' \
      '"=""9780446675505""",5,4.28,Grand Central Publishing,Paperback,345,2000,1993,2020/03/15,2019/11/02,' \
      '"to-read, sci-fi","to-read (#1), sci-fi (#4)",to-read,,,,0,0'
  end

  # No ISBN13, unrated, and only an exclusive shelf.
  def piranesi
    '50202953,Piranesi,Susanna Clarke,"Clarke, Susanna",,"=""1526622424""","=""""",0,4.24,Bloomsbury,Hardcover,272,,2020,,2021/07/04,,,read,,,,1,1'
  end

  def csv *rows
    [headers, *rows].join("\n")
  end

  describe '.parse' do
    it 'maps a row onto the book hash shape the rest of the app reads' do
      book = GoodreadsCsv.parse(csv(sower)).first

      assert_equal 'Parable of the Sower (Earthseed, #1)', book[:title]
      assert_equal 'Octavia E. Butler', book[:author]
      assert_equal '2000', book[:published_year]
    end

    it 'unwraps the Excel-wrapped ISBN columns and prefers ISBN13' do
      book = GoodreadsCsv.parse(csv(sower)).first

      assert_equal '9780446675505', book[:isbn]
    end

    it 'falls back to ISBN when ISBN13 is blank' do
      book = GoodreadsCsv.parse(csv(piranesi)).first

      assert_equal '1526622424', book[:isbn]
    end

    it 'keeps My Rating as an integer, with 0 meaning unrated' do
      rated, unrated = GoodreadsCsv.parse csv(sower, piranesi)

      assert_equal 5, rated[:ratings]
      assert_equal 0, unrated[:ratings]
    end

    it 'normalizes Date Added to a lexicographically sortable ISO date' do
      book = GoodreadsCsv.parse(csv(sower)).first

      assert_equal '2019-11-02', book[:date_added]
    end

    it 'falls back to Original Publication Year when Year Published is blank' do
      book = GoodreadsCsv.parse(csv(piranesi)).first

      assert_equal '2020', book[:published_year]
    end

    it 'leaves image_url nil because the export carries no cover URLs' do
      book = GoodreadsCsv.parse(csv(sower)).first

      assert_nil book[:image_url]
    end

    it 'lists the exclusive shelf first, then the named bookshelves' do
      book = GoodreadsCsv.parse(csv(sower)).first

      assert_equal %w[to-read sci-fi], book[:shelves]
    end

    it 'does not repeat the exclusive shelf when Bookshelves also names it' do
      book = GoodreadsCsv.parse(csv(sower.sub('"to-read, sci-fi"', '"to-read"'))).first

      assert_equal %w[to-read], book[:shelves]
    end

    it 'skips rows with no title rather than importing a blank book' do
      assert_empty GoodreadsCsv.parse(csv(sower.sub('"Parable of the Sower (Earthseed, #1)"', '""')))
    end

    it 'tolerates a UTF-8 byte order mark' do
      books = GoodreadsCsv.parse "﻿#{csv(sower)}"

      assert_equal 1, books.length
    end

    it 'tolerates CRLF line endings' do
      books = GoodreadsCsv.parse [headers, sower].join("\r\n")

      assert_equal 'Octavia E. Butler', books.first[:author]
    end

    it 'accepts an IO rather than a string' do
      books = GoodreadsCsv.parse StringIO.new(csv(sower))

      assert_equal 1, books.length
    end

    it 'rejects a CSV that is not a Goodreads export' do
      error = assert_raises(GoodreadsCsv::InvalidFormat) { GoodreadsCsv.parse "name,qty\nwidget,2" }

      assert_includes error.message, 'goodreads.com/review/import'
    end

    it 'rejects a file with Title but no distinctly Goodreads column' do
      assert_raises(GoodreadsCsv::InvalidFormat) { GoodreadsCsv.parse "Title,Author\nPiranesi,Clarke" }
    end

    it 'rejects empty input' do
      assert_raises(GoodreadsCsv::InvalidFormat) { GoodreadsCsv.parse '' }
    end
  end

  describe '.shelf_counts' do
    it 'counts books per shelf, largest first' do
      counts = GoodreadsCsv.shelf_counts GoodreadsCsv.parse(csv(sower, piranesi))

      assert_equal [['read', 1], ['sci-fi', 1], ['to-read', 1]], counts
    end

    it 'orders by count before name' do
      books = [{shelves: %w[small big]}, {shelves: %w[big]}]

      assert_equal [['big', 2], ['small', 1]], GoodreadsCsv.shelf_counts(books)
    end
  end

  describe '.books_on' do
    it 'returns only the books carrying that shelf' do
      books = GoodreadsCsv.parse csv(sower, piranesi)
      titles = GoodreadsCsv.books_on(books, 'read').map { |book| book[:title] }

      assert_equal %w[Piranesi], titles
    end

    it 'returns nothing for an unknown shelf' do
      assert_empty GoodreadsCsv.books_on(GoodreadsCsv.parse(csv(sower)), 'nope')
    end
  end
end
