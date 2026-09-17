# frozen_string_literal: true

require_relative 'spec_helper'
require 'goodreads'

# The one Goodreads case where a cassette beats a stub: a full 250-book shelf
# across three pages. Building that payload inline would be 250 hand-written
# <review> elements, and the schema has to be exact -- extract_books_from_body
# maps seven xpaths and transposes them, so one missing field produces ragged
# arrays and an IndexError from inside Array#transpose rather than a readable
# failure.
#
# The cassette is committed, so this runs offline. Delete
# spec/fixtures/cassettes/goodreads_shelf_three_pages.yml and run with a real
# GOODREADS_API_KEY to re-record; `record: :once` will write it back with the
# key filtered out.
#
# NOTE: the committed cassette was generated to match the schema the parser
# expects, not captured from live Goodreads. Re-recording it against the real
# API is worth doing whenever someone has working credentials in hand -- that
# is what would catch a schema change, which is the whole point of a cassette.
describe 'Goodreads shelf from a cassette' do
  it 'reads every book across all three pages' do
    books = with_cassette('goodreads_shelf_three_pages') { Goodreads.get_books('to-read', '42') }

    assert_equal 250, books.size
  end

  it 'parses the fields the stats views read' do
    book = with_cassette('goodreads_shelf_three_pages') { Goodreads.get_books('to-read', '42') }.first

    assert_match(/\A978\d{10}\z/, book[:isbn])
    assert_match(/\ARecorded Book \d+\z/, book[:title])
    assert_match(/\AAuthor \d+\z/, book[:author])
    refute_empty book[:published_year].to_s
  end

  it 'feeds the aggregations the stats page renders' do
    books = with_cassette('goodreads_shelf_three_pages') { Goodreads.get_books('to-read', '42') }

    assert_equal 250, Goodreads.plot_books_over_time(books).size
    assert_equal 250, Goodreads.rating_stats(books).values.sum
  end
end
