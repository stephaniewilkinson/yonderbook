# frozen_string_literal: true

require 'uri'

# Builds a URL that shows a book in OverDrive's public catalogue.
#
# Deliberately not a Libby deep link and deliberately not the authenticated
# API. Libby is a single page app: https://libbyapp.com/search/query-Piranesi
# answers 200 with an empty shell titled "Libby" and renders nothing useful to
# someone following a link. A real deep link needs a library-specific path,
# which the caller does not have -- the Signal bot has a title, sometimes an
# author, and no ISBN or consortium.
#
# https://www.overdrive.com/search?q=... is server rendered and works with no
# key, no token and no library chosen. Verified against the live site:
#
#   q=Piranesi                            -> "87 results for Piranesi"
#   q=Piranesi Susanna Clarke             -> "34 results for ..."
#   q=Parable of the Sower Octavia Butler -> "25 results for ..."
#
# Including the author narrows sensibly, so it is used when present.
module LibbyUrl
  SEARCH = 'https://www.overdrive.com/search'

  module_function

  # Returns a search URL, or nil when there is no title to search for.
  def for title, author = nil
    terms = [title, author].map { |term| term.to_s.strip }.reject(&:empty?)
    return if terms.empty?

    "#{SEARCH}?#{URI.encode_www_form(q: terms.join(' '))}"
  end
end
