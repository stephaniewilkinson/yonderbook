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

  def handle_import_routes request
    rodauth.require_login

    # route: GET /import
    request.get true do
      @shelf_counts = ImportedBook.shelf_counts @user.id
      @book_count = @shelf_counts.empty? ? 0 : ImportedBook.where(user_id: @user.id).count
      view 'import'
    end

    # route: POST /import
    request.post true do
      check_csrf!
      count = import_csv_upload request
      request.redirect '/import' unless count

      flash[:notice] = "Imported #{count} book#{'s' unless count == 1} from your Goodreads export."
      request.redirect '/goodreads/shelves'
    end

    # route: POST /import/clear
    request.post 'clear' do
      check_csrf!
      ImportedBook.clear @user.id
      flash[:notice] = 'Your imported library has been removed.'
      request.redirect '/import'
    end
  end

  # Reads an uploaded Goodreads CSV export and replaces the account's library.
  # Returns the number of books stored, or nil after setting a flash error.
  def import_csv_upload request
    upload = request.params['library']
    return reject_import 'Choose the CSV file you downloaded from Goodreads.' unless upload.is_a?(Hash) && upload[:tempfile]
    return reject_import 'That file is too large to be a Goodreads export.' if upload[:tempfile].size > MAX_IMPORT_BYTES

    books = GoodreadsCsv.parse upload[:tempfile]
    return reject_import 'That export does not have any books in it.' if books.empty?
    return reject_import "That export has more than #{MAX_IMPORT_BOOKS} books, which is more than we can store." if books.size > MAX_IMPORT_BOOKS

    ImportedBook.replace_library @user.id, books
  rescue GoodreadsCsv::InvalidFormat => e
    reject_import e.message
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
