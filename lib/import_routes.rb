# frozen_string_literal: true

require_relative 'goodreads_csv'

# Routes and helpers for importing a Goodreads CSV library export.
#
# An export needs no API key and no OAuth, so this is the one path into a user's
# shelves that does not depend on the Goodreads API Amazon deprecated in 2020.
module ImportRoutes
  # A Goodreads export is a few hundred KB at most; anything larger is not one,
  # and parsing it would be a memory risk on a 512MB instance.
  MAX_IMPORT_BYTES = 10 * 1024 * 1024
  MAX_IMPORT_BOOKS = 20_000
  # A visitor without an account gets their library held in the session cache
  # instead (#1414): nothing about them reaches the database. A parsed book is
  # about 1.1KB resident, so this is ~5.5MB per visitor for the cache's 15
  # minutes. Generous for a want-to-read list; a whole library can go into an
  # account, which streams to SQLite instead.
  ANONYMOUS_MAX_BOOKS = 5_000

  def handle_import_routes request
    # route: GET /import
    request.get true do
      if @user
        @shelf_counts = ImportedBook.shelf_counts @user.id
        @book_count = @shelf_counts.empty? ? 0 : ImportedBook.where(user_id: @user.id).count
      else
        library = anonymous_library || []
        @shelf_counts = GoodreadsCsv.shelf_counts library
        @book_count = library.size
      end
      @shelves_path = shelves_path
      view 'import'
    end

    # route: POST /import
    request.post true do
      check_csrf!
      count = @user ? import_csv_upload(request) : import_anonymous_csv_upload(request)
      request.redirect '/import' unless count

      flash['fathom_event'] = 'csv_uploaded'
      flash[:notice] = "Imported #{count} book#{'s' unless count == 1} from your Goodreads export."
      request.redirect shelves_path
    end

    # route: POST /import/clear
    request.post 'clear' do
      check_csrf!
      @user ? ImportedBook.clear(@user.id) : Cache.set(session, anonymous_library: nil)
      flash[:notice] = 'Your imported library has been removed.'
      request.redirect '/import'
    end
  end

  # Reads an uploaded Goodreads CSV export and replaces the account's library.
  # Returns the number of books stored, or nil after setting a flash error.
  def import_csv_upload request
    file = uploaded_export(request) or return

    # Streamed, not parsed into an array: a large library must never be resident
    # in memory all at once here. See GoodreadsCsv.each_book.
    count = ImportedBook.replace_library @user.id, GoodreadsCsv.each_book(file), max: MAX_IMPORT_BOOKS
    return reject_import 'That export does not have any books in it.' if count.zero?

    count
  rescue GoodreadsCsv::InvalidFormat => e
    reject_import e.message
  rescue ImportedBook::TooManyBooks
    reject_import "That export has more than #{MAX_IMPORT_BOOKS} books, which is more than we can store."
  end

  # The same upload for a visitor without an account, held in the session cache
  # and nowhere else. Deduplicated the way ImportedBook stores a library, so the
  # copy saved at sign-up matches what they saw.
  def import_anonymous_csv_upload request
    file = uploaded_export(request) or return

    books = []
    seen = {}
    GoodreadsCsv.each_book(file) do |book|
      key = ImportedBook.dedupe_key book
      next if seen.key? key
      return reject_import too_many_for_anonymous if books.length >= ANONYMOUS_MAX_BOOKS

      seen[key] = true
      books << book
    end
    return reject_import 'That export does not have any books in it.' if books.empty?

    Cache.set session, anonymous_library: books
    books.length
  rescue GoodreadsCsv::InvalidFormat => e
    reject_import e.message
  end

  def too_many_for_anonymous
    "That export has more than #{ANONYMOUS_MAX_BOOKS} books. Create a free account to import up to #{MAX_IMPORT_BOOKS}."
  end

  # The uploaded file, or nil after setting a flash error.
  def uploaded_export request
    upload = request.params['library']
    return reject_import 'Choose the CSV file you downloaded from Goodreads.' unless upload.is_a?(Hash) && upload[:tempfile]
    return reject_import 'That file is too large to be a Goodreads export.' if upload[:tempfile].size > MAX_IMPORT_BYTES

    upload[:tempfile]
  end

  def reject_import message
    flash[:error] = message
    nil
  end

  # An uploaded library takes precedence over the API: the user chose to upload
  # it, it is durable, and reading it never touches the deprecated endpoints.
  def imported_library?
    return @imported_library if defined?(@imported_library)

    @imported_library = @user ? ImportedBook.imported?(@user.id) : false
  end

  # Returns [] rather than nil for an unknown shelf, so callers treat a missing
  # imported shelf as empty instead of falling back to the Goodreads API.
  def imported_shelf_books
    return unless imported_library?

    ImportedBook.books_on @user.id, @shelf_name
  end

  def shelf_list
    imported_library? ? ImportedBook.shelf_counts(@user.id) : Goodreads.fetch_shelves(@goodreads_user_id)
  end
end
