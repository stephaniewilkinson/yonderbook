# frozen_string_literal: true

# Shared by the authenticated availability page and its anonymous twin. Both
# read the same four cached values and split the titles the same four ways;
# only where an incomplete flow sends the visitor back to differs, so that
# stays with each route.
module AvailabilityHelpers
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

  def load_cached_availability
    @titles = Cache.get session, :titles
    @collection_token = Cache.get session, :collection_token
    @website_id = Cache.get session, :website_id
    @library_url = Cache.get session, :library_url
  end

  def split_titles_by_availability
    @available_books = sort_by_date_added(@titles.select { |a| a.copies_available.positive? })
    @waitlist_books = sort_by_date_added(@titles.select { |a| a.copies_available.zero? && a.copies_owned.positive? })
    @no_isbn_books = sort_by_date_added(@titles.select(&:no_isbn))
    @unavailable_books = sort_by_date_added(@titles.select { |a| a.copies_owned.zero? && !a.no_isbn })
  end
end
