# frozen_string_literal: true

require_relative 'spec_helper'
require 'date_added'

describe DateAdded do
  def book title, date_added
    Struct.new(:title, :date_added).new title, date_added
  end

  def titles books
    books.map(&:title)
  end

  describe '.sort_desc' do
    # The original bug: a plain string sort on this format orders by weekday
    # abbreviation, which put a 2015 book above a 2024 one.
    it 'orders the Goodreads RFC 2822 format by date, not by weekday name' do
      books = [
        book('2024', 'Mon Jan 01 00:00:00 -0800 2024'),
        book('2019', 'Fri Sep 20 12:00:00 -0700 2019'),
        book('2021', 'Tue Mar 05 08:00:00 -0800 2021'),
        book('2025', 'Wed Dec 31 23:00:00 -0800 2025'),
        book('2015', 'Sat Feb 14 10:00:00 -0800 2015')
      ]

      assert_equal %w[2025 2024 2021 2019 2015], titles(DateAdded.sort_desc(books))
    end

    it 'orders ISO dates newest first' do
      books = [book('older', '2015-01-01'), book('newer', '2024-06-01')]

      assert_equal %w[newer older], titles(DateAdded.sort_desc(books))
    end

    it 'compares the two formats against each other' do
      books = [book('iso-2015', '2015-01-01'), book('rfc-2024', 'Mon Jan 01 00:00:00 -0800 2024')]

      assert_equal %w[rfc-2024 iso-2015], titles(DateAdded.sort_desc(books))
    end

    it 'sorts a nil date last instead of raising' do
      books = [book('undated', nil), book('dated', '2015-01-01')]

      assert_equal %w[dated undated], titles(DateAdded.sort_desc(books))
    end

    it 'sorts an empty date last' do
      books = [book('blank', ''), book('dated', '2015-01-01')]

      assert_equal %w[dated blank], titles(DateAdded.sort_desc(books))
    end

    it 'sorts an unparseable date last instead of raising' do
      books = [book('garbage', 'not a date'), book('dated', '2015-01-01')]

      assert_equal %w[dated garbage], titles(DateAdded.sort_desc(books))
    end

    it 'returns an empty list unchanged' do
      assert_empty DateAdded.sort_desc([])
    end
  end

  describe '.to_time' do
    it 'parses the Goodreads RFC 2822 format' do
      assert_equal 2024, DateAdded.to_time('Mon Jan 01 00:00:00 -0800 2024').year
    end

    it 'parses an ISO date' do
      assert_equal 2019, DateAdded.to_time('2019-11-02').year
    end

    it 'falls back to the epoch for nil' do
      assert_equal DateAdded::EPOCH, DateAdded.to_time(nil)
    end

    it 'falls back to the epoch for an unparseable value' do
      assert_equal DateAdded::EPOCH, DateAdded.to_time('not a date')
    end
  end
end
