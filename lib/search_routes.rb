# frozen_string_literal: true

# Anonymous search routes for users who connected Goodreads without an account
module SearchRoutes
  def handle_search_routes request
    require_goodreads_session request

    request.on('shelves') { anonymous_shelf_routes request }
    request.on('library') { anonymous_library_routes request }
    request.on('availability') { anonymous_availability_routes request }
  end

  def anonymous_shelf_routes request
    # route: GET /search/shelves
    request.get true do
      @shelves = Goodreads.fetch_shelves @goodreads_user_id
      view 'search/shelves'
    end

    request.on String do |shelf_name|
      @shelf_name = shelf_name
      Cache.set session, shelf_name: @shelf_name

      # route: GET /search/shelves/:name
      request.get true do
        @book_info = anonymous_shelf_books
        @histogram_dataset = Goodreads.plot_books_over_time @book_info
        @ratings = Goodreads.rating_stats @book_info
        view 'shelves/show'
      end

      # route: GET /search/shelves/:name/overdrive
      #
      # Renders a zip code form and nothing else, so it deliberately does not
      # load the shelf -- doing that is what timed out the authenticated
      # equivalent in #1333.
      request.get 'overdrive' do
        @library_action = '/search/library'
        view 'shelves/overdrive'
      end
    end
  end

  def anonymous_library_routes request
    # route: POST /search/library?zipcode=90029
    request.post true do
      check_csrf!
      @shelf_name = Cache.get session, :shelf_name
      zip = request.params['zipcode'].to_s
      reject_zip request, 'You need to enter a zip code' if zip.empty?
      reject_zip request, 'Please try a different zip code' unless Geolocation.known_zip?(zip)

      Cache.set session, libraries: fetch_local_libraries(request, zip, fallback: zip_form_path)
      request.redirect '/search/library'
    end

    # route: GET /search/library
    request.get true do
      @shelf_name = Cache.get session, :shelf_name
      @local_libraries = Cache.get session, :libraries
      unless @local_libraries
        flash[:error] = @shelf_name ? 'Please enter your zip code first' : 'Please choose a shelf first'
        request.redirect @shelf_name ? zip_form_path : '/search/shelves'
      end
      @availability_action = '/search/availability'
      view 'library'
    end
  end

  def anonymous_availability_routes request
    # route: POST /search/availability?consortium=1047
    request.post true do
      check_csrf!
      @shelf_name = Cache.get session, :shelf_name
      consortium = typecast_params.pos_int('consortium')
      reject_library request, 'Invalid library selection' unless consortium

      book_info = anonymous_shelf_books
      if book_info.nil? || book_info.empty?
        flash[:error] = "We couldn't read that shelf from Goodreads. Please pick a shelf and try again."
        request.redirect '/search/shelves'
      end

      cache_anonymous_availability request, book_info, consortium
      request.redirect '/search/availability'
    end

    # route: GET /search/availability
    request.get true do
      load_cached_availability
      unless @titles
        # Resume at the furthest step already completed, the same way the
        # authenticated page does.
        @shelf_name = Cache.get session, :shelf_name
        libraries = Cache.get session, :libraries
        flash[:error] = libraries ? 'Please choose a library first' : 'Please choose a shelf first'
        request.redirect libraries ? '/search/library' : '/search/shelves'
      end
      split_titles_by_availability
      @anonymous_search = true
      @library_action = '/search/library'
      view 'availability'
    end
  end

  # Kept out of the route block so the rescue covers the OverDrive calls and
  # nothing else -- wrapping the whole block would swallow the CSRF rejection,
  # which has to reach the app's handler.
  def cache_anonymous_availability request, book_info, consortium
    overdrive = Overdrive.new(book_info, consortium)
    titles = overdrive.fetch_titles_availability
    Cache.set(session, titles:, collection_token: overdrive.collection_token, website_id: overdrive.website_id, library_url: overdrive.library_url)
  rescue Overdrive::ApiError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    reject_library request, 'We could not reach OverDrive for that library. Please try another.'
  end

  def anonymous_shelf_books
    cached_or_fetch(@shelf_name.to_sym) { Goodreads.get_books(@shelf_name, @goodreads_user_id, @anon_access_token) }
  end

  def reject_library request, message
    flash[:error] = message
    request.redirect '/search/library'
  end

  def zip_form_path
    @shelf_name ? "/search/shelves/#{@shelf_name}/overdrive" : '/search/shelves'
  end

  def reject_zip request, message
    flash[:error] = message
    request.redirect zip_form_path
  end
end
