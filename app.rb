# frozen_string_literal: true

system 'roda-parse_routes', '-f', 'routes.json', __FILE__

require 'area'
require 'rack/host_redirect'
require 'roda'
require 'rollbar/middleware/rack'
require 'securerandom'
require 'tilt'
require 'zbar'
require_relative 'lib/auth'
require_relative 'lib/bookmooch'
require_relative 'lib/cache'
require_relative 'lib/db'
require_relative 'lib/goodreads'
require_relative 'lib/models'
require_relative 'lib/overdrive'

class App < Roda
  use Rollbar::Middleware::Rack
  use Rack::HostRedirect, 'bookmooch.herokuapp.com' => 'yonderbook.com'

  plugin :halt
  plugin :head
  plugin :assets, css: 'styles.css'
  plugin :public, root: 'assets'
  plugin :flash
  plugin :sessions, secret: ENV.fetch('SESSION_SECRET')
  plugin :slash_path_empty
  plugin :render

  compile_assets
  # TODO: figure out how to reroute 404s to /
  route do |r|
    r.public
    r.assets

    @books = DB[:books]
    @users = DB[:users]

    session['session_id'] ||= SecureRandom.uuid

    r.root do
      request_token = Auth.fetch_request_token
      Cache.set session, request_token: request_token

      # route: GET /
      r.get true do
        @auth_url = request_token.authorize_url
        view 'welcome'
      end
    end

    r.on 'login' do
      # route: GET /login
      r.get do
        request_token = Cache.get session, :request_token

        goodreads_user_id = Goodreads.fetch_user request_token
        session['goodreads_user_id'] = goodreads_user_id
        r.redirect '/auth/shelves'
      end
    end

    r.on 'about' do
      # route: GET /about
      r.get do
        view 'about'
      end
    end

    r.on 'auth' do
      @user = @users.first(goodreads_user_id: session['goodreads_user_id'])
      r.redirect '/' unless @user
      @goodreads_user_id = @user[:goodreads_user_id]

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
            access_token = Auth.rebuild_access_token @user
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
              r.halt(403) if r['username'] == 'susanb'
              @books_added, @books_failed = Bookmooch.books_added_and_failed @book_info, r['username'], r['password']
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

          r.on 'overdrive' do
            # TODO: have browser get their location
            # route: GET /auth/shelves/:id/overdrive
            r.get true do
              view 'shelves/overdrive'
            end

            # route: POST /auth/shelves/:id/overdrive?consortium=1047
            r.post do
              titles = Overdrive.new(@book_info, r['consortium']).fetch_titles_availability
              Cache.set session, titles: titles
              r.redirect '/auth/availability'
            end
          end
        end
      end

      r.on 'availability' do
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
      r.on 'library' do
        # route: POST /auth/library?zipcode=90029
        r.post do
          @shelf_name = Cache.get session, :shelf_name
          zip = r['zipcode']

          if zip.empty?
            flash[:error] = 'You need to enter a zip code'
            r.redirect "shelves/#{@shelf_name}/overdrive"
          end

          unless zip.to_latlon
            flash[:error] = 'please try a different zip code'
            r.redirect "shelves/#{@shelf_name}/overdrive"
          end

          @local_libraries = Overdrive.local_libraries zip.to_latlon.delete ' '

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

      r.on 'inventory' do
        # route: GET /auth/inventory/new
        r.get 'new' do
          view 'inventory/new'
        end

        # route: GET /inventory/:id
        r.get Integer do |book_id|
          @book = @books.first(id: book_id)
          @user = @users.first(id: @book[:user_id])
          view 'inventory/show'
        end

        # route: POST /auth/inventory/create?barcode_image="isbn.jpg"
        r.post 'create' do
          image = r[:barcode_image][:tempfile]
          barcodes = ZBar::Image.from_jpeg(image).process

          if barcodes.any?
            r.redirect '/' unless goodreads_user_id

            barcodes.each do |barcode|
              isbn = barcode.data
              status, book = Goodreads.fetch_book_data isbn

              raise "#{status}: #{book}" unless status == :ok

              @books.insert isbn: isbn, user_id: @user[:id], cover_image_url: book.image_url, title: book.title
            end
            r.redirect '/inventory/index'
          else
            flash[:error] = 'no barcode detected, please try again'
            r.redirect 'auth/inventory/new'
          end
        end

        # route: GET /auth/inventory
        r.get do
          view 'inventory/index'
        end
      end

      r.on 'users' do
        # TODO: write authorization for these routes properly
        # route: GET /auth/users
        r.get true do
          # TODO: make a jwt
          if session['goodreads_user_id'] == '7208734'
            view 'users/index'
          else
            view 'welcome'
          end
        end

        r.on String do |id|
          # route: GET /auth/users/:id
          r.get true do
            if @user == @users.first(id: id)
              view 'users/show'
            else
              view 'welcome'
            end
          end

          # route: GET /auth/users/:id/edit
          r.get 'edit' do
            view 'users/edit'
          end

          # route: POST /auth/users/:id
          r.post true do
            @users.where(goodreads_user_id: @goodreads_user_id).update(
              email: r.params['email'],
              first_name: r.params['first_name'],
              last_name: r.params['last_name']
            )
            @user = @users.where(goodreads_user_id: @goodreads_user_id).first
            view 'users/show'
          end
        end
      end
    end
  end
end
