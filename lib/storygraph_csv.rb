# frozen_string_literal: true

require 'date'

# Maps a row of a StoryGraph CSV export to the book hash GoodreadsCsv builds,
# so a StoryGraph library feeds the same import, availability and alerts.
# GoodreadsCsv detects the export from its headers and calls this for its rows.
#
# The format, from several independent importers (StoryGraph doesn't document
# it): Title, Authors, Contributors, ISBN/UID, Format, Read Status, Date Added,
# Last Date Read, Dates Read, Read Count, Moods, Pace, ..., Star Rating, Review,
# Content Warnings, Content Warning Description, Tags, Owned?
module StorygraphCsv
  # Distinctly StoryGraph, alongside Title.
  SIGNATURE_COLUMNS = ['ISBN/UID', 'Read Status'].freeze

  module_function

  def matches? headers
    SIGNATURE_COLUMNS.all? { |column| headers.include? column }
  end

  def book_from row
    title = GoodreadsCsv.text row['Title']
    return unless title

    status = read_status row['Read Status']
    {
      goodreads_book_id: nil,
      isbn: isbn(row['ISBN/UID']),
      image_url: nil,
      title:,
      author: first_author(row['Authors']),
      published_year: nil,
      ratings: GoodreadsCsv.text(row['Star Rating']).to_f.round,
      date_added: iso_date(row['Date Added']),
      exclusive_shelf: status,
      shelves: [status, *tags(row['Tags'])].compact.uniq
    }
  end

  # "to-read", "currently-reading", "read", "did-not-finish": the same names
  # Goodreads uses where they overlap, so "to-read" is the shelf people pick.
  def read_status value
    GoodreadsCsv.text(value)&.downcase&.tr(' _', '--')
  end

  # StoryGraph puts its own id here when it has no ISBN; only a real ISBN is
  # any use to OverDrive or BookMooch.
  def isbn value
    digits = GoodreadsCsv.text(value).to_s.delete('-')
    digits if digits.match?(/\A(\d{9}[\dXx]|\d{13})\z/)
  end

  # "Ursula K. Le Guin, Some Translator": the first is the author.
  def first_author value
    authors = GoodreadsCsv.text(value) or return
    authors.split(',').first.strip
  end

  def tags value
    GoodreadsCsv.text(value).to_s.split(',').map(&:strip).reject(&:empty?)
  end

  # Importers report YYYY/MM/DD, YYYY-MM-DD and "Month D, YYYY". Anything
  # unreadable is dropped rather than guessed: it only orders the list.
  def iso_date value
    raw = GoodreadsCsv.text(value) or return
    return GoodreadsCsv.iso_date(raw) if raw.match?(%r{\A\d{4}[/-]\d{1,2}[/-]\d{1,2}\z})

    Date.parse(raw).iso8601
  rescue Date::Error
    nil
  end
end
