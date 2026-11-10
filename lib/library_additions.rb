# frozen_string_literal: true

# Availability alerts, part 2 (#1422): "your library added it".
#
# A book none of a reader's libraries had when they turned alerts on is kept as
# a WantedBook. Once a week AvailabilityAlerts.check asks this module to search
# for those again; a copy a library now owns becomes a WatchedTitle, and one
# that is free right away goes into that day's email.
module LibraryAdditions
  # The search costs one OverDrive title search per book per library, so it
  # is capped per reader per run, taking a random sample so a long list is
  # covered over a few weeks.
  SEARCH_LIMIT = 500
  # A little under a week, so a daily run a few hours early still counts.
  SEARCH_INTERVAL = (7 * 24 * 3600) - (4 * 3600)

  module_function

  # Books from the list with no copy owned at any of the libraries checked.
  def wanted_rows user_id, books, titles
    owned = titles.select { |copy| copy.copies_owned.to_i.positive? }.to_set { |copy| Overdrive.book_key(copy.isbn, copy.title) }
    rows = Array(books).filter_map do |book|
      next if book[:title].to_s.empty? || owned.include?(Overdrive.book_key(book[:isbn], book[:title]))

      {user_id: user_id, title: book[:title], author: book[:author], isbn: book[:isbn]}
    end
    rows.uniq { |row| Overdrive.book_key(row[:isbn], row[:title]) }
  end

  def due? subscription, now
    subscription.last_searched_at.nil? || subscription.last_searched_at < now - SEARCH_INTERVAL
  end

  # Searches each library, in the reader's order, for wanted books, and turns
  # what a library now owns into unsaved WatchedTitles. A book found at one
  # library isn't searched at the next. Returns those and the WantedBook ids
  # found, which stop being wanted. A library that fails is skipped this week.
  def find subscription, search
    wanted = WantedBook.where(user_id: subscription.user_id).order(Sequel.function(:random)).limit(SEARCH_LIMIT).all
    by_key = wanted.to_h { |book| [Overdrive.book_key(book.isbn, book.title), book] }
    found = Set.new
    additions = subscription.library_list.flat_map do |consortium_id, library_name|
      remaining = by_key.except(*found).values
      next [] if remaining.empty?

      owned_copies(search, consortium_id, remaining).map do |copy|
        found << Overdrive.book_key(copy.isbn, copy.title)
        addition subscription.user_id, consortium_id, library_name, copy
      end
    end
    [additions.uniq { |row| [row.consortium_id, row.reserve_id] }, by_key.slice(*found).values.map(&:id)]
  end

  # Copies a library owns among the books searched for, or none if the
  # library's search fails (it is retried next week).
  def owned_copies search, consortium_id, books
    search.call(consortium_id.to_s, books.map(&:to_book)).select { |copy| copy.id && copy.copies_owned.to_i.positive? }
  rescue StandardError => e
    Sentry.capture_exception e
    []
  end

  def addition user_id, consortium_id, library_name, copy
    WatchedTitle.new(
      user_id: user_id,
      consortium_id: consortium_id.to_s,
      reserve_id: copy.id.downcase,
      title: copy.title,
      author: copy.author,
      format: copy.format,
      library_name: library_name,
      url: copy.url,
      copies_available: copy.copies_available.to_i,
      copies_owned: copy.copies_owned.to_i
    )
  end

  # Ignores a copy already watched (the same product at the same library).
  def save additions, now:, notified:
    additions.each do |row|
      values = row.values.merge(last_checked_at: now)
      values[:notified_at] = now if notified && row.copies_available.positive?
      WatchedTitle.dataset.insert_conflict.insert values
    end
  end

  def overdrive_search consortium_id, books
    Overdrive.new(books, consortium_id).fetch_titles_availability
  end
end
