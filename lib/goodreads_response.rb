# frozen_string_literal: true

require 'nokogiri'

# Reads Goodreads XML, insisting the element we asked for is actually there.
#
# The API is deprecated and answers a revoked key, an expired OAuth token or a
# rate limit with a non-200 or with XML that simply omits the element. Left
# unchecked those degrade silently -- an empty shelf list, or an opaque
# NoMethodError on nil several lines further along.
module GoodreadsResponse
  # Raised when Goodreads answers with something we can't read.
  class ApiError < StandardError; end

  # How much of an unexpected body to quote back, so a failure names its cause.
  SUMMARY_LENGTH = 200

  module_function

  # Returns the node at xpath, or raises ApiError describing what came back.
  def parse status, body, xpath
    raise ApiError, "Goodreads returned HTTP #{status} for #{xpath}: #{summarize body}" unless status == 200

    node = Nokogiri::XML(body).at_xpath xpath
    raise ApiError, "Goodreads response has no #{xpath}: #{summarize body}" unless node

    node
  end

  def summarize body
    body.to_s.gsub(/\s+/, ' ').strip[0, SUMMARY_LENGTH]
  end
end
