# frozen_string_literal: true

require_relative 'spec_helper'
require 'goodreads_response'

describe GoodreadsResponse do
  # What Goodreads actually sends when it rejects a key: a plain-text line
  # followed by a random-length HTML comment, and no XML at all.
  def rejection_body
    "Invalid API key.\n<!-- This is a random-length HTML comment: abcdef -->"
  end

  def shelves_body
    '<GoodreadsResponse><shelves total="2"><user_shelf><name>read</name></user_shelf></shelves></GoodreadsResponse>'
  end

  describe '.parse' do
    it 'returns the requested node on a well-formed response' do
      node = GoodreadsResponse.parse 200, shelves_body, '//shelves'

      assert_equal 'shelves', node.name
      assert_equal '2', node['total']
    end

    it 'raises on a non-200 and quotes what came back' do
      error = assert_raises GoodreadsResponse::ApiError do
        GoodreadsResponse.parse 401, rejection_body, '//reviews'
      end

      assert_includes error.message, 'HTTP 401'
      assert_includes error.message, '//reviews'
      assert_includes error.message, 'Invalid API key.'
    end

    # Goodreads sometimes answers 200 with a body that has nothing in it. This
    # used to surface far away as NoMethodError on nil.
    it 'raises when a 200 response omits the element' do
      error = assert_raises GoodreadsResponse::ApiError do
        GoodreadsResponse.parse 200, rejection_body, '//reviews'
      end

      assert_includes error.message, 'has no //reviews'
    end

    it 'raises rather than returning nil for an empty body' do
      assert_raises GoodreadsResponse::ApiError do
        GoodreadsResponse.parse 200, '', '//reviews'
      end
    end
  end

  describe '.summarize' do
    it 'collapses whitespace so the message stays on one line' do
      assert_equal 'Invalid API key. <!-- x -->', GoodreadsResponse.summarize("Invalid API key.\n  <!-- x -->\n")
    end

    it 'caps the quoted body' do
      assert_equal GoodreadsResponse::SUMMARY_LENGTH, GoodreadsResponse.summarize('x' * 500).length
    end

    it 'handles a nil body' do
      assert_equal '', GoodreadsResponse.summarize(nil)
    end
  end
end
