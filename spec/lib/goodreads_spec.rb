# frozen_string_literal: true

require_relative 'spec_helper'
require 'goodreads'

describe Goodreads do
  describe '.get_gender' do
    it 'counts female, male, and androgynous names' do
      books = [
        {title: 'Emily Goes Home', author: 'Someone'},
        {title: 'James and the Giant Peach', author: 'Someone'},
        {title: 'Pat Runs Away', author: 'Someone'}
      ]
      women, men, andy = Goodreads.get_gender(books)
      assert_equal 1, women
      assert_equal 1, men
      assert_equal 1, andy
    end

    it 'returns zero for empty book lists' do
      women, men, andy = Goodreads.get_gender([])
      assert_equal 0, women
      assert_equal 0, men
      assert_equal 0, andy
    end
  end

  describe '.plot_books_over_time' do
    it 'returns title and year pairs' do
      books = [{title: 'Book A', published_year: '2020'}, {title: 'Book B', published_year: '1999'}]
      result = Goodreads.plot_books_over_time(books)
      assert_equal [['Book A', 2020], ['Book B', 1999]], result
    end

    it 'skips books with empty published year' do
      books = [{title: 'Book A', published_year: '2020'}, {title: 'Book B', published_year: ''}]
      result = Goodreads.plot_books_over_time(books)
      assert_equal [['Book A', 2020]], result
    end
  end

  describe '.rating_stats' do
    it 'groups books by rating' do
      books = [{ratings: '5'}, {ratings: '5'}, {ratings: '3'}, {ratings: '0'}]
      stats = Goodreads.rating_stats(books)
      assert_equal 2, stats[5]
      assert_equal 1, stats[3]
      unrated = 0
      assert_equal 1, stats[unrated]
    end

    it 'falls back to :rating when :ratings is nil' do
      books = [{rating: '4', ratings: nil}]
      stats = Goodreads.rating_stats(books)
      assert_equal 1, stats[4]
    end
  end

  describe '.get_book_details' do
    it 'parses XML bodies into book hashes' do
      xml = <<~XML
        <response>
          <reviews>
            <review>
              <isbn13>9780140328721</isbn13>
              <book>
                <image_url>http://example.com/cover.jpg</image_url>
                <id>77203</id>
              </book>
              <title>The Outsiders</title>
              <authors><author><name>S.E. Hinton</name></author></authors>
              <published>1967</published>
              <rating>5</rating>
              <date_added>Mon Jan 01 00:00:00 -0800 2024</date_added>
            </review>
          </reviews>
        </response>
      XML

      result = Goodreads.get_book_details([xml])
      assert_equal 1, result.size
      book = result.first
      assert_equal '9780140328721', book[:isbn]
      assert_equal 'The Outsiders', book[:title]
      assert_equal 'S.E. Hinton', book[:author]
      assert_equal '1967', book[:published_year]
      assert_equal '5', book[:ratings]
      assert_equal '77203', book[:goodreads_id]
    end
  end
end
