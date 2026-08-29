# frozen_string_literal: true

# Anonymous search routes for users who connected Goodreads without an account
module SearchRoutes
  def handle_search_routes request
    require_goodreads_session request

    request.on('shelves') { anonymous_shelf_routes request }
    request.on('library') { anonymous_library_routes request }
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

  def anonymous_shelf_books
    cached_or_fetch(@shelf_name.to_sym) { Goodreads.get_books(@shelf_name, @goodreads_user_id, @anon_access_token) }
  end

  def zip_form_path
    @shelf_name ? "/search/shelves/#{@shelf_name}/overdrive" : '/search/shelves'
  end

  def reject_zip request, message
    flash[:error] = message
    request.redirect zip_form_path
  end
end
