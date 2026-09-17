# frozen_string_literal: true

# Shared by the authenticated availability page and its anonymous twin. Both
# read the same four cached values and split the titles the same four ways;
# only where an incomplete flow sends the visitor back to differs, so that
# stays with each route.
module AvailabilityHelpers
  # Where "Search library" goes when the library's own OverDrive address is
  # unknown. library_url is derived from a dlrHomepage link that not every
  # consortium returns, and an empty "?websiteID=" -- which is what the view
  # used to render in that case -- is a link to nowhere.
  OVERDRIVE_HOME = 'https://www.overdrive.com/libraries'

  # Hand the OverDrive check to the WebSocket rather than running it inline.
  # RequestTimeout caps a request at 25s to stay under Render's proxy, and a
  # large shelf takes longer than that (#1347); the middleware exempts WebSocket
  # upgrades, so that is where the work can actually finish.
  #
  # Any titles from a previous library are cleared first, so the progress page
  # cannot redirect to stale results if this run fails.
  def queue_availability_check book_info, consortium
    Cache.set(session, titles: nil)
    Cache.set(session, availability_book_info: book_info, availability_consortium: consortium)
  end

  # Two of the four values this used to read -- collection_token and
  # website_id -- were cached, read back, assigned, and used by nothing.
  # website_id existed only so the view could rebuild the borrow URL that
  # Overdrive#library_url already returns.
  def load_cached_availability
    @titles = Cache.get session, :titles
    @library_url = Cache.get session, :library_url
  end

  # "Read" is wrong on an audiobook, and every result carried it because
  # nothing read the product's mediaType (#542).
  def listen_or_read title
    title.format == 'audiobook' ? 'Listen' : 'Read'
  end

  def split_titles_by_availability
    @available_books = sort_by_date_added(@titles.select { |a| a.copies_available.positive? })
    @waitlist_books = sort_by_date_added(@titles.select { |a| a.copies_available.zero? && a.copies_owned.positive? })
    @no_isbn_books = sort_by_date_added(@titles.select(&:no_isbn))
    @unavailable_books = sort_by_date_added(@titles.select { |a| a.copies_owned.zero? && !a.no_isbn })
  end
end
