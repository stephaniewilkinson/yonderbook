# frozen_string_literal: true

class App
  hash_branch 'connections' do |r|
    # route: GET /connections
    r.get true do
      @goodreads_connection = @user&.goodreads_connection
      view 'connections'
    end

    r.on 'goodreads' do
      # route: GET /connections/goodreads
      r.get true do
        r.redirect '/home' if @user&.goodreads_connected?
        request_token = fetch_and_cache_request_token
        @auth_url = request_token&.authorize_url
        view 'connect_goodreads'
      end

      # Require Goodreads connection for shelves
      r.on 'shelves' do
        unless @user&.goodreads_connected?
          flash[:error] = 'Please connect your Goodreads account first'
          r.redirect '/connections/goodreads'
        end

        load_goodreads_connection

        # route: GET /connections/goodreads/shelves
        r.get true do
          @shelves = Goodreads.fetch_shelves @goodreads_user_id
          Analytics.track session['session_id'], 'shelves_viewed', shelf_count: @shelves.size
          view 'shelves/index'
        end

        # TODO: change this so I'm not passing stuff back and forth from cache unnecessarily
        r.on String do |shelf_name|
          @shelf_name = shelf_name
          Cache.set session, shelf_name: @shelf_name
          @book_info = Cache.get(session, @shelf_name.to_sym) || load_background_shelf_data

          # route: GET /connections/goodreads/shelves/:id
          r.get true do
            @book_info ||= load_or_start_shelf_import(@shelf_name)
            view('shelves/loading') unless @book_info
            @women, @men, @andy = Goodreads.get_gender @book_info
            @histogram_dataset = Goodreads.plot_books_over_time @book_info
            @ratings = Goodreads.rating_stats @book_info
            Analytics.track session['session_id'], 'shelf_stats_viewed', shelf: @shelf_name, book_count: @book_info.size
            view 'shelves/show'
          end

          # Blocking fetch for sub-routes that need @book_info
          @book_info ||= fetch_shelf_blocking(@shelf_name)

          r.on 'bookmooch' do
            # route: GET /connections/goodreads/shelves/:id/bookmooch
            r.get true do
              @new_count, @skip_count, @no_isbn_count = bookmooch_preview(@user.id, @book_info)
              view 'shelves/bookmooch'
            end

            # route: POST /connections/goodreads/shelves/:id/bookmooch?username=foo&password=baz
            r.post do
              BookmoochImport.clear_imports(@user.id) if r.params['reimport'] == '1'
              filtered = filter_already_imported_books(@user.id, @book_info)
              cache_bookmooch_params(r, filtered, @user.id, @book_info.size - filtered.size)
              set_pending_import('bookmooch', "#{r.path}/results", progress_url: "#{r.path}/progress")
              r.redirect 'bookmooch/progress'
            end

            # route: GET /connections/goodreads/shelves/:id/bookmooch/progress
            r.get 'progress' do
              @session_id = session['session_id']
              view 'bookmooch_progress'
            end

            r.get 'results' do # route: GET /connections/goodreads/shelves/:id/bookmooch/results
              @books_added, @books_failed, @books_failed_no_isbn, @skipped_count = load_bookmooch_results
              view 'bookmooch'
            end
          end

          r.is 'overdrive' do
            r.get(true) { view 'shelves/overdrive' } # route: GET /connections/goodreads/shelves/:id/overdrive
            r.post do # route: POST /connections/goodreads/shelves/:id/overdrive?consortium=1047
              consortium = r.params['consortium']
              unless consortium&.match?(/\A\d+\z/)
                flash[:error] = 'Invalid library selection'
                r.redirect "shelves/#{@shelf_name}/overdrive"
              end
              overdrive = Overdrive.new(@book_info, consortium)
              titles = overdrive.fetch_titles_availability
              Cache.set(session, titles:, collection_token: overdrive.collection_token, website_id: overdrive.website_id, library_url: overdrive.library_url)
              Analytics.track session['session_id'], 'overdrive_search', shelf: @shelf_name, consortium: consortium, titles_found: titles.size
              r.redirect '/connections/goodreads/availability'
            end
          end
        end
      end

      r.is 'availability' do
        unless @user&.goodreads_connected?
          flash[:error] = 'Please connect your Goodreads account first'
          r.redirect '/connections/goodreads'
        end

        load_goodreads_connection
        r.get do # route: GET /connections/goodreads/availability
          @titles = Cache.get session, :titles
          @collection_token = Cache.get session, :collection_token
          @website_id = Cache.get session, :website_id
          @library_url = Cache.get session, :library_url
          unless @titles
            flash[:error] = 'Please choose a shelf first'
            r.redirect 'shelves'
          end
          @available_books = sort_by_date_added(@titles.select { |a| a.copies_available.positive? })
          @waitlist_books = sort_by_date_added(
            @titles.select do |a|
              a.copies_available.zero? && a.copies_owned.positive?
            end
          )
          @no_isbn_books = sort_by_date_added(@titles.select(&:no_isbn))
          @unavailable_books = sort_by_date_added(@titles.select { |a| a.copies_owned.zero? && !a.no_isbn })
          Analytics.track session['session_id'],
                          'availability_viewed',
                          available: @available_books.size,
                          waitlist: @waitlist_books.size,
                          unavailable: @unavailable_books.size
          view 'availability'
        end
      end

      r.is 'library' do
        unless @user&.goodreads_connected?
          flash[:error] = 'Please connect your Goodreads account first'
          r.redirect '/connections/goodreads'
        end
        load_goodreads_connection
        r.post do # route: POST /connections/goodreads/library?zipcode=90029
          @shelf_name = Cache.get session, :shelf_name
          zip = r.params['zipcode'].to_s

          if zip.empty?
            flash[:error] = 'You need to enter a zip code'
            r.redirect "shelves/#{@shelf_name}/overdrive"
          end
          unless zip.to_latlon
            flash[:error] = 'please try a different zip code'
            r.redirect "shelves/#{@shelf_name}/overdrive"
          end
          @local_libraries = Overdrive.local_libraries zip.delete ' '
          Cache.set session, libraries: @local_libraries
          Analytics.track session['session_id'], 'library_search', zipcode: zip, libraries_found: @local_libraries.size
          r.redirect '/connections/goodreads/library'
        end

        # route: GET /connections/goodreads/library
        r.get do
          @shelf_name = Cache.get session, :shelf_name
          @local_libraries = Cache.get session, :libraries
          # TODO: see if we can bring the person back to the choose a library stage
          # rather than all the way back to choose a shelf
          unless @local_libraries
            flash[:error] = 'Please choose a shelf first'
            r.redirect 'shelves'
          end
          view 'library'
        end
      end
    end
  end
end
