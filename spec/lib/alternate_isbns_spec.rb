# frozen_string_literal: true

require_relative 'spec_helper'
require 'alternate_isbns'

describe AlternateIsbns do
  describe '.isbn_13_to_isbn_10' do
    it 'converts a valid ISBN-13 to ISBN-10' do
      assert_equal '0140328726', AlternateIsbns.isbn_13_to_isbn_10('9780140328721')
    end

    it 'handles check digit X' do
      assert_equal '080701429X', AlternateIsbns.isbn_13_to_isbn_10('9780807014295')
    end

    it 'returns nil for non-978 prefix' do
      assert_nil AlternateIsbns.isbn_13_to_isbn_10('9790000000000')
    end

    it 'returns nil for wrong length' do
      assert_nil AlternateIsbns.isbn_13_to_isbn_10('978012345')
    end

    it 'returns nil for nil input' do
      assert_nil AlternateIsbns.isbn_13_to_isbn_10(nil)
    end
  end

  describe '.extract_isbns_from_edition' do
    it 'extracts ISBN-13s and converts to ISBN-10s' do
      edition = {'isbn_13' => %w[9780140328721], 'isbn_10' => []}
      isbns = AlternateIsbns.extract_isbns_from_edition(edition)

      assert_includes isbns, '9780140328721'
      assert_includes isbns, '0140328726'
    end

    it 'includes ISBN-10s from edition data' do
      edition = {'isbn_13' => [], 'isbn_10' => %w[0140328726]}
      isbns = AlternateIsbns.extract_isbns_from_edition(edition)
      assert_includes isbns, '0140328726'
    end

    it 'handles missing ISBN fields' do
      edition = {}
      isbns = AlternateIsbns.extract_isbns_from_edition(edition)
      assert_empty isbns
    end

    it 'deduplicates results' do
      edition = {'isbn_13' => %w[9780140328721], 'isbn_10' => %w[0140328726]}
      isbns = AlternateIsbns.extract_isbns_from_edition(edition)
      assert_equal isbns, isbns.uniq
    end
  end

  describe '.extract_isbns_from_editions' do
    it 'collects ISBNs from multiple editions' do
      editions = [{'isbn_13' => %w[9780140328721], 'isbn_10' => []}, {'isbn_13' => %w[9780141311234], 'isbn_10' => []}]
      isbns = AlternateIsbns.extract_isbns_from_editions(editions)
      assert_includes isbns, '9780140328721'
      assert_includes isbns, '9780141311234'
    end
  end

  describe '.extract_work_key' do
    it 'extracts work key from edition data' do
      edition = {'works' => [{'key' => '/works/OL45804W'}]}
      assert_equal 'OL45804W', AlternateIsbns.extract_work_key(edition)
    end

    it 'returns nil when no works present' do
      assert_nil AlternateIsbns.extract_work_key({})
    end

    it 'returns nil when works array is empty' do
      assert_nil AlternateIsbns.extract_work_key({'works' => []})
    end
  end
end
