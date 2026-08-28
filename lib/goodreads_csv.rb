# frozen_string_literal: true

require 'csv'

# Parses a Goodreads CSV library export into the same book hash shape
# lib/goodreads.rb builds from the API, so an imported shelf can feed OverDrive
# availability and BookMooch without touching the deprecated Goodreads API.
#
# Depends on nothing but the csv stdlib on purpose: lib/goodreads.rb ENV.fetches
# API credentials at load time, and importing a file must not require them.
module GoodreadsCsv
  # Raised when an upload is not a Goodreads library export.
  class InvalidFormat < RuntimeError; end

  # Goodreads wraps the ISBN columns for Excel: ="0765376679", blank as ="".
  EXCEL_WRAPPED = /\A="(.*)"\z/
  # 'Title' alone is too generic to identify the file, so at least one
  # distinctly Goodreads column has to appear alongside it.
  SIGNATURE_COLUMNS = ['Book Id', 'Exclusive Shelf'].freeze
  BYTE_ORDER_MARK = '﻿'
  FORMAT_HELP = "That does not look like a Goodreads library export. Download yours from goodreads.com/review/import using the 'Export Library' button."

  module_function

  # Returns an array of book hashes carrying the keys the rest of the app
  # already reads -- :isbn, :image_url, :title, :author, :published_year,
  # :ratings, :date_added -- plus :goodreads_book_id, :exclusive_shelf and
  # :shelves for persistence.
  def parse source
    each_book(source).to_a
  end

  # Yields one book at a time, holding a single row rather than the library.
  #
  # A 20k-book export is only ~4MB on disk, but materialized as an array of
  # hashes it costs ~100MB of RSS -- a real risk on a 512MB instance that
  # already OOMs (see the README). The import path consumes this lazily so peak
  # memory is bounded by the insert batch, not by how many books someone owns.
  def each_book source
    return enum_for(:each_book, source) unless block_given?

    csv = CSV.new decode(source), headers: true
    row = csv.shift
    validate_headers csv.headers
    while row
      book = book_from row
      yield book if book
      row = csv.shift
    end
  rescue CSV::MalformedCSVError => e
    raise InvalidFormat, "That file could not be read as CSV: #{e.message.lines.first.to_s.strip}"
  end

  # [[shelf_name, book_count], ...], largest shelf first, ties broken by name.
  def shelf_counts books
    counts = Hash.new 0
    books.each { |book| book[:shelves].each { |shelf| counts[shelf] += 1 } }
    counts.sort_by { |name, count| [-count, name] }
  end

  def books_on books, shelf_name
    books.select { |book| book[:shelves].include? shelf_name }
  end

  def decode source
    raw = source.respond_to?(:read) ? source.read : source.to_s
    raw.dup.force_encoding(Encoding::UTF_8).scrub.delete_prefix BYTE_ORDER_MARK
  end

  def validate_headers headers
    present = Array(headers).compact
    raise InvalidFormat, FORMAT_HELP unless present.include? 'Title'
    raise InvalidFormat, FORMAT_HELP if SIGNATURE_COLUMNS.none? { |column| present.include? column }
  end

  def book_from row
    title = text row['Title']
    return unless title

    {
      goodreads_book_id: text(row['Book Id']),
      isbn: unwrap(row['ISBN13']) || unwrap(row['ISBN']),
      image_url: nil,
      title:,
      author: text(row['Author']),
      published_year: published_year(row),
      ratings: row['My Rating'].to_i,
      date_added: iso_date(row['Date Added']),
      exclusive_shelf: text(row['Exclusive Shelf']),
      shelves: shelves(row)
    }
  end

  # Exclusive Shelf first so it reads as the primary shelf; Goodreads repeats it
  # inside Bookshelves for some exports and omits it in others.
  def shelves row
    listed = text(row['Bookshelves']).to_s.split(',').map(&:strip).reject(&:empty?)
    [text(row['Exclusive Shelf']), *listed].compact.uniq
  end

  def published_year row
    text(row['Year Published']) || text(row['Original Publication Year'])
  end

  # Goodreads writes YYYY/MM/DD. Normalized to ISO so the value sorts
  # lexicographically -- see #439, where sorting the API's RFC-2822 strings
  # orders by weekday name rather than by date.
  def iso_date value
    raw = text value
    return unless raw

    year, month, day = raw.split %r{[/-]}
    return raw unless day

    format '%<year>04d-%<month>02d-%<day>02d', year: year.to_i, month: month.to_i, day: day.to_i
  end

  def unwrap value
    inner = text value
    return unless inner

    match = EXCEL_WRAPPED.match inner
    text(match ? match[1] : inner)
  end

  def text value
    return if value.nil?

    stripped = value.to_s.strip
    stripped.empty? ? nil : stripped
  end
end
