# frozen_string_literal: true

# Shared by the authenticated availability page and its anonymous twin. Both
# read the same four cached values and split the titles the same four ways;
# only where an incomplete flow sends the visitor back to differs, so that
# stays with each route.
module AvailabilityHelpers
  # Each library is a full extra pass over the shelf -- the product search is
  # scoped to a collection token, so every book is searched again per
  # consortium, and that search is already the slowest thing the app does.
  # Early exit keeps the real cost well under N passes, but an unbounded
  # selection is still a request that will not finish.
  MAX_LIBRARIES = 3

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
  def queue_availability_check book_info, libraries
    Cache.set(session, titles: nil)
    Cache.set(session, availability_book_info: book_info, availability_libraries: libraries)
  end

  # The consortium ids a reader picked, paired with their names, capped and in
  # the order they were offered. Returns [] when nothing valid was chosen.
  def chosen_libraries request
    picked = Array(request.params['consortium']).map(&:to_s).reject(&:empty?)
    return [] if picked.empty?

    available = Cache.get(session, :libraries) || []
    available.filter_map { |id, name| [id.to_s, name] if picked.include?(id.to_s) }.first(MAX_LIBRARIES)
  end

  # Two of the four values this used to read -- collection_token and
  # website_id -- were cached, read back, assigned, and used by nothing.
  # website_id existed only so the view could rebuild the borrow URL that
  # Overdrive#library_url already returns.
  def load_cached_availability
    @titles = Cache.get session, :titles
    @library_url = Cache.get session, :library_url
    @library_names = Cache.get(session, :library_names) || []
  end

  # "Read" is wrong on an audiobook, and every result carried it because
  # nothing read the product's mediaType (#542).
  def listen_or_read title
    title.format == 'audiobook' ? 'Listen' : 'Read'
  end

  # One book, and every copy of it found: each format, at each library.
  #
  # Copies are sorted best-first, so `best` is what decides which tab the book
  # appears under. A reader asks "can I get this book", not "what does each
  # library have", so the row is the book and the copies are what they can do
  # about it (#1390).
  Book = Data.define(:title, :author, :image, :isbn, :no_isbn, :date_added, :copies) do
    def best = copies.first

    def libraries = copies.filter_map(&:library).uniq

    def formats = copies.map(&:format).uniq
  end

  # Each copy of a book as a row the results page can render: where it is,
  # what format, and what the reader can do about it.
  def copy_rows copies, action: :borrow
    copies.map do |copy|
      {
        library: copy.library,
        format: Overdrive.format_label(copy.format),
        status_value: copy.copies_owned.to_i == 999_999 ? 'Unlimited' : "#{copy.copies_available}/#{copy.copies_owned}",
        button: {
          url: copy.url,
          icon: '/svg/book.svg',
          label: action == :reserve ? 'Reserve' : listen_or_read(copy),
          class: 'bg-mauve-950 hover:bg-mauve-900'
        }
      }
    end
  end

  # "Brooklyn" / "Brooklyn and NYPL" / "Brooklyn, NYPL and Queens".
  def sentence names
    return names.first.to_s if names.size <= 1

    "#{names[0..-2].join(', ')} and #{names.last}"
  end

  def group_copies_into_books copies
    copies.group_by { |copy| Overdrive.book_key(copy.isbn, copy.title) }.map do |_key, found|
      ranked = found.sort_by { |copy| [-copy.copies_available.to_i, -copy.copies_owned.to_i] }
      first = ranked.first
      Book.new(
        title: first.title,
        author: first.author,
        image: first.image,
        isbn: first.isbn,
        no_isbn: first.no_isbn,
        date_added: first.date_added,
        copies: ranked
      )
    end
  end

  # A book lands in the tab its best copy earns: available anywhere beats
  # waitlisted anywhere, which beats owned nowhere.
  def split_titles_by_availability
    books = group_copies_into_books @titles
    @available_books = sort_by_date_added(books.select { |book| book.best.copies_available.to_i.positive? })
    @waitlist_books = sort_by_date_added(books.select { |book| book.best.copies_available.to_i.zero? && book.best.copies_owned.to_i.positive? })
    @no_isbn_books = sort_by_date_added(books.select(&:no_isbn))
    @unavailable_books = sort_by_date_added(books.select { |book| book.best.copies_owned.to_i.zero? && !book.no_isbn })
  end
end
