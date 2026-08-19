# frozen_string_literal: true

require_relative 'spec_helper'
require 'overdrive/library_search'

describe Overdrive::LibrarySearch do
  def libraries_json
    '[{"consortiumId":1683,"consortiumName":"San Francisco Public Library","consortiumLogo":"/logo.png"}]'
  end

  # What the public site returns when it blocks or throttles a request.
  def blocked_body
    '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"><HTML><HEAD><TITLE>ERROR</TITLE></HEAD></HTML>'
  end

  describe '.parse' do
    it 'returns the parsed consortia on a well-formed response' do
      libraries = Overdrive::LibrarySearch.parse 200, libraries_json, '94103'

      assert_equal 1, libraries.size
      assert_equal 'San Francisco Public Library', libraries.first['consortiumName']
    end

    # No libraries near a zip is a real answer, not a failure.
    it 'passes an empty list through without raising' do
      assert_empty Overdrive::LibrarySearch.parse(200, '[]', '99999')
    end

    it 'raises on a non-200 and names the zip code' do
      error = assert_raises Overdrive::ApiError do
        Overdrive::LibrarySearch.parse 403, blocked_body, '94103'
      end

      assert_includes error.message, 'HTTP 403'
      assert_includes error.message, '94103'
    end

    # Previously surfaced as a bare JSON::ParserError with no hint of the cause.
    it 'raises when a 200 response carries HTML instead of JSON' do
      error = assert_raises Overdrive::ApiError do
        Overdrive::LibrarySearch.parse 200, blocked_body, '94103'
      end

      assert_includes error.message, 'non-JSON'
      assert_includes error.message, 'TITLE>ERROR'
    end
  end
end
