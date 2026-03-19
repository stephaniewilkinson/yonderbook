# frozen_string_literal: true

require_relative 'spec_helper'
require 'bookmooch'

describe Bookmooch do
  describe '.expand_isbns_with_alternates' do
    it 'adds alternate ISBNs and maps back to originals' do
      originals = %w[111 222]
      alternate_map = {'111' => %w[333 444], '222' => %w[555]}

      expanded, isbn_to_original = Bookmooch.expand_isbns_with_alternates(originals, alternate_map)

      assert_includes expanded, '111'
      assert_includes expanded, '333'
      assert_includes expanded, '444'
      assert_includes expanded, '222'
      assert_includes expanded, '555'
      assert_equal '111', isbn_to_original['333']
      assert_equal '111', isbn_to_original['444']
      assert_equal '222', isbn_to_original['555']
    end

    it 'deduplicates expanded ISBNs' do
      originals = %w[111]
      alternate_map = {'111' => %w[111 222]}

      expanded, = Bookmooch.expand_isbns_with_alternates(originals, alternate_map)
      assert_equal %w[111 222], expanded
    end

    it 'handles empty alternate map' do
      originals = %w[111 222]

      expanded, isbn_to_original = Bookmooch.expand_isbns_with_alternates(originals, {})
      assert_equal %w[111 222], expanded
      assert_equal '111', isbn_to_original['111']
      assert_equal '222', isbn_to_original['222']
    end
  end

  describe '.map_to_originals_with_best_isbn' do
    it 'maps added ISBNs back to originals' do
      isbn_to_original = {'111' => '111', '333' => '111', '222' => '222'}
      added_isbns = %w[333 222]

      originals, best = Bookmooch.map_to_originals_with_best_isbn(added_isbns, isbn_to_original)

      assert_includes originals, '111'
      assert_includes originals, '222'
      assert_equal '333', best['111']
      assert_equal '222', best['222']
    end

    it 'picks the first added ISBN as best for each original' do
      isbn_to_original = {'111' => '111', '333' => '111', '444' => '111'}
      added_isbns = %w[444 333 111]

      _, best = Bookmooch.map_to_originals_with_best_isbn(added_isbns, isbn_to_original)
      assert_equal '444', best['111']
    end
  end

  describe '.auth_headers' do
    it 'returns Basic auth header' do
      headers = Bookmooch.auth_headers('user', 'pass')
      expected = Base64.strict_encode64('user:pass')
      assert_equal "Basic #{expected}", headers['Authorization']
    end
  end

  describe '.collect_added_isbns' do
    it 'collects ISBNs from response body' do
      added = []
      Bookmooch.collect_added_isbns("111\n222\n333\n", added)
      assert_equal %w[111 222 333], added
    end

    it 'handles nil response body' do
      added = []
      Bookmooch.collect_added_isbns(nil, added)
      assert_empty added
    end
  end
end
