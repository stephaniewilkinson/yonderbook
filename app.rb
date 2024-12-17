# frozen_string_literal: true

system 'roda-parse_routes', '-f', 'routes.json', __FILE__

require 'area'
require 'rack/host_redirect'
require 'roda'
require 'rollbar/middleware/rack'
require 'securerandom'
require 'tilt'
# require 'zbar'

require_relative 'lib/auth'
require_relative 'lib/bookmooch'
require_relative 'lib/cache'
require_relative 'lib/goodreads'
require_relative 'lib/overdrive'

class App < Roda
  use Rollbar::Middleware::Rack
  use Rack::HostRedirect, 'bookmooch.herokuapp.com' => 'yonderbook.com'

  plugin :head
  plugin :assets, css: 'styles.css'
  plugin :public, root: 'assets'
  plugin :flash
  plugin :sessions, secret: ENV.fetch('SESSION_SECRET')
  plugin :slash_path_empty
  plugin :render
  plugin :default_headers, 'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains'

  compile_assets
  # TODO: figure out how to reroute 404s to /
  route do |r|
    r.public
    r.assets

    session['session_id'] ||= SecureRandom.uuid

    # route: GET /
    r.root do
      request_token = Auth.fetch_request_token
      Cache.set(session, request_token:)

      @auth_url = request_token.authorize_url
      view 'welcome'
    end

    r.is 'login' do
      request_token = Cache.get session, :request_token
      # TODO: this is blocking people who are already logged in but not a huge deal
      unless request_token
        flash[:error] = 'Please authenticate first'
        r.redirect '/'
      end

      # route: GET /login
      r.get do
        goodreads_user_id, access_token, access_token_secret = Goodreads.fetch_user request_token
        session['access_token'] = access_token
        session['access_token_secret'] = access_token_secret

        session['goodreads_user_id'] = goodreads_user_id

        r.redirect '/auth/shelves'
      rescue OAuth::Unauthorized
        flash[:error] = 'Fetched details! Click login'
        r.redirect '/'
      end
    end

    r.is 'about' do
      # route: GET /about
      r.get do
        view 'about'
      end
    end

    r.on 'auth' do
      @goodreads_user_id = session['goodreads_user_id']
      r.redirect '/' unless @goodreads_user_id

      # TODO: change this so I'm not passing stuff back and forth from cache unnecessarily
      r.on 'shelves' do
        # route: GET /auth/shelves
        r.get true do
          @shelves = Goodreads.fetch_shelves @goodreads_user_id
          view 'shelves/index'
        end

        r.on String do |shelf_name|
          @shelf_name = shelf_name
          Cache.set session, shelf_name: @shelf_name

          @book_info = Cache.get session, @shelf_name.to_sym
          unless @book_info
            access_token = Auth.rebuild_access_token(session['access_token'], session['access_token_secret'])
            @book_info = Goodreads.get_books @shelf_name, @goodreads_user_id, access_token
            Cache.set session, @shelf_name.to_sym => @book_info
          end

          # route: GET /auth/shelves/:id
          r.get true do
            @women, @men, @andy = Goodreads.get_gender @book_info
            @histogram_dataset = Goodreads.plot_books_over_time @book_info
            @ratings = Goodreads.rating_stats @book_info

            view 'shelves/show'
          end

          r.on 'bookmooch' do
            # route: GET /auth/shelves/:id/bookmooch
            r.get true do
              view 'shelves/bookmooch'
            end

            # route: POST /auth/shelves/:id/bookmooch?username=foo&password=baz
            r.post do
              @books_added, @books_failed = Bookmooch.books_added_and_failed @book_info, r.params['username'], r.params['password']
              Cache.set session, books_added: @books_added, books_failed: @books_failed

              r.redirect 'bookmooch/results'
            end

            # route: GET /auth/shelves/:id/bookmooch/results
            r.get 'results' do
              @books_added = Cache.get session, :books_added
              @books_failed = Cache.get session, :books_failed
              view 'bookmooch'
            end
          end

          r.is 'overdrive' do
            # TODO: have browser get their location
            # route: GET /auth/shelves/:id/overdrive
            r.get true do
              view 'shelves/overdrive'
            end

            # route: POST /auth/shelves/:id/overdrive?consortium=1047
            r.post do
              titles = Overdrive.new(@book_info, r.params['consortium']).fetch_titles_availability
              Cache.set(session, titles:)
              r.redirect '/auth/availability'
            end
          end
        end
      end

      r.is 'availability' do
        # route: GET /auth/availability
        r.get do
          # TODO: Sort titles by recently added to goodreads list
          @titles = Cache.get session, :titles

          unless @titles
            flash[:error] = 'Please choose a shelf first'
            r.redirect 'shelves'
          end

          @available_books = @titles.select { |a| a.copies_available.positive? }
          @waitlist_books = @titles.select { |a| a.copies_available.zero? && a.copies_owned.positive? }
          @unavailable_books = @titles.select { |a| a.copies_owned.zero? }
          view 'availability'
        end
      end

      # TODO: add library logos to the cards in the views
      r.is 'library' do
        # route: POST /auth/library?zipcode=90029
        r.post do
          @shelf_name = Cache.get session, :shelf_name
          zip = r.params['zipcode']

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
          r.redirect '/auth/library'
        end

        # route: GET /auth/library
        r.get do
          @shelf_name = Cache.get session, :shelf_name
          @local_libraries = Cache.get session, :libraries
          # TODO: see if we can bring the person back to the choose a library stage rather than all the way back to choose a shelf
          unless @local_libraries
            flash[:error] = 'Please choose a shelf first'
            r.redirect 'shelves'
          end
          view 'library'
        end
      end
    end
  rescue OAuth::Unauthorized, StandardError, ScriptError => e
    raise e unless ENV['RACK_ENV'] == 'production'

    r.redirect '/'
  end
end
