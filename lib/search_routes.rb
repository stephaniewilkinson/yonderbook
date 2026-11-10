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
      @shelves = anonymous_library ? GoodreadsCsv.shelf_counts(anonymous_library) : Goodreads.fetch_shelves(@goodreads_user_id)
      view 'search/shelves'
    end

    request.on String do |shelf_name|
      @shelf_name = shelf_name
      Cache.set session, shelf_name: @shelf_name

      # route: GET /search/shelves/:name
      # Loaded in the background like the signed-in stats page: a large
      # shelf fetched inline ran past the request timeout.
      request.get true do
        @book_info = anonymous_ready_books || load_or_start_shelf_import(@shelf_name, return_to: request.path)
        next view('shelves/loading') unless @book_info

        @histogram_dataset = Goodreads.plot_books_over_time @book_info
        @ratings = Goodreads.rating_stats @book_info
        view 'shelves/show'
      end

      # route: GET /search/shelves/:name/overdrive
      #
      # The zip code form. Never loads the shelf inline -- that is what timed
      # out the authenticated equivalent in #1333 -- but starts it loading in
      # the background, so it is usually in by the time libraries are picked.
      request.get 'overdrive' do
        @book_info = anonymous_ready_books
        preload_shelf request
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
      zip = Geolocation.normalize_zip request.params['zipcode']
      reject_zip request, 'You need to enter a zip code' if zip.empty?
      reject_zip request, "We don't recognize that zip code. Please try another.", event: 'zip_not_recognized' unless Geolocation.known_zip?(zip)

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
    request.post(true) { start_anonymous_availability request }

    # route: GET /search/availability/continue
    # Waits for the shelf on the loading page, then runs the check (ShelfLoading).
    request.get 'continue' do
      @shelf_name = Cache.get(session, :shelf_name) or request.redirect('/search/shelves')
      @book_info = anonymous_ready_books
      continue_availability request, progress_path: '/search/availability/progress', libraries_path: '/search/library'
    end

    # route: GET /search/availability/progress
    request.get 'progress' do
      @session_id = session['session_id']
      @results_path = '/search/availability'
      @retry_path = '/search/library'
      view 'availability_progress'
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

  def start_anonymous_availability request
    check_csrf!
    @shelf_name = Cache.get session, :shelf_name
    libraries = chosen_libraries request
    reject_library request, 'Please choose at least one library' if libraries.empty?
    unless @shelf_name
      flash[:error] = 'Please choose a shelf first'
      request.redirect '/search/shelves'
    end

    @book_info = anonymous_ready_books
    book_info = shelf_or_wait request, libraries, '/search/availability/continue'

    # Same reason as the authenticated twin: the OverDrive check does not fit
    # in a request (#1347), so the WebSocket runs it.
    queue_availability_check book_info, libraries
    request.redirect '/search/availability/progress'
  end

  # The shelf if it is already to hand, or nil. An uploaded export wins over a
  # Goodreads connection, as it does for an account: the visitor chose it, and
  # it never touches the deprecated API. Otherwise it is whatever is cached or
  # a background fetch has finished; nothing here fetches from Goodreads.
  def anonymous_ready_books
    return GoodreadsCsv.books_on(anonymous_library, @shelf_name) if anonymous_library

    Cache.get(session, @shelf_name.to_sym) || load_background_shelf_data
  end

  def reject_library request, message
    flash[:error] = message
    request.redirect '/search/library'
  end

  # The zip code form for the shelf in hand, signed in or not.
  def zip_form_path
    @shelf_name ? "#{shelves_path}/#{@shelf_name}/overdrive" : shelves_path
  end

  # event: a Fathom event to report on the page the redirect lands on (#1411).
  def reject_zip request, message, to: zip_form_path, event: nil
    flash[:error] = message
    flash['fathom_event'] = event if event
    request.redirect to
  end
end
