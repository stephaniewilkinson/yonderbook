# frozen_string_literal: true

require_relative 'spec_helper'

# The anonymous flow walked end to end: OAuth callback, shelf list, zip code,
# library, results. Split from anonymous_search_spec.rb, which covers the route
# guards -- the negative paths for a visitor with no credentials.
#
# All of this was blocked until the suite could stub Goodreads and OverDrive at
# the HTTP layer (#1382); before that it needed a live API key and a real shelf
# on a real account.
describe 'Anonymous search flow, end to end' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  def with_anonymous_session(cached = {}, &)
    values = ANON_CREDENTIALS.merge(cached)
    Cache.stub(:get, ->(_session, key) { values[key] }, &)
  end

  # Cases 4, 7, 8, 9, 10 and 11 of #1264. All six were blocked until the suite
  # could stub Goodreads and OverDrive at the HTTP layer (#1382) -- before that
  # they needed a live API key and a real shelf on a real account.

  describe 'GET /search-callback' do
    it 'exchanges the request token and sends the visitor to their shelves' do
      token = Struct.new(:token, :secret).new('req-token', 'req-secret')
      credentials = {user_id: '7', token: 'access-token', secret: 'access-secret'}

      Cache.stub(:get, ->(_session, key) { key == :request_token ? token : nil }) do
        Goodreads.stub(:exchange_token, credentials) do
          stored = {}
          Cache.stub(:set, ->(_session, values) { stored.merge!(values) }) do
            get '/search-callback'

            assert_equal '/search/shelves', last_response.headers['location']
            assert_equal '7', stored[:anon_goodreads_user_id]
            assert_equal 'access-token', stored[:anon_goodreads_token]
          end
        end
      end
    end

    # The Goodreads double-click: the first authorize can come back rejected,
    # and the visitor has to be told to press it again rather than shown a 500.
    it 'asks for another click when Goodreads rejects the exchange' do
      token = Struct.new(:token, :secret).new('req-token', 'req-secret')

      Cache.stub(:get, ->(_session, key) { key == :request_token ? token : nil }) do
        Goodreads.stub(:exchange_token, ->(*) { raise OAuth::Unauthorized, Net::HTTPUnauthorized.new('1.1', '401', 'Unauthorized') }) do
          get '/search-callback'

          assert_equal '/', last_response.headers['location']
        end
      end
    end
  end

  describe 'GET /search/shelves with credentials' do
    it 'renders the shelf list fetched from Goodreads' do
      stub_request(:get, HttpFixtures::SHELF_LIST_URL).to_return(status: 200, body: HttpFixtures.goodreads_shelf_list([['to-read', 12], ['sci-fi', 4]]))

      with_anonymous_session do
        get '/search/shelves'

        assert_equal 200, last_response.status
        assert_includes last_response.body, 'to-read'
        assert_includes last_response.body, 'sci-fi'
      end
    end

    it 'asks Goodreads for the shelves of the session user, not some default' do
      stub_request(:get, HttpFixtures::SHELF_LIST_URL).to_return(status: 200, body: HttpFixtures.goodreads_shelf_list([['to-read', 1]]))

      with_anonymous_session do
        get '/search/shelves'

        assert_requested(:get, /user_id=#{ANON_CREDENTIALS[:anon_goodreads_user_id]}/, times: 1)
      end
    end
  end

  describe 'POST /search/library' do
    # shelf_name has to be in the session: zip_form_path builds the redirect
    # target from it, and without one every rejection lands on /search/shelves.
    def post_zip zipcode, session_values = {}
      with_anonymous_session({shelf_name: 'to-read'}.merge(session_values)) do
        get '/search/shelves/to-read/overdrive'
        csrf = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
        post '/search/library', 'zipcode' => zipcode, '_csrf' => csrf
      end
    end

    it 'sends a valid zip code to the library picker' do
      stub_request(:get, HttpFixtures::FIND_LIBRARIES_URL).to_return(status: 200, body: JSON.dump([HttpFixtures.overdrive_library]))

      post_zip '94103'

      assert_equal '/search/library', last_response.headers['location']
    end

    it 'strips spaces before asking OverDrive' do
      stub_request(:get, HttpFixtures::FIND_LIBRARIES_URL).to_return(status: 200, body: JSON.dump([HttpFixtures.overdrive_library]))

      post_zip '941 03'

      assert_requested(:get, /query=94103/, times: 1)
    end

    it 'sends an empty zip code back to the form' do
      post_zip ''

      assert_equal '/search/shelves/to-read/overdrive', last_response.headers['location']
    end

    # OverDrive answers a blocked network with HTML rather than JSON. The
    # visitor gets the zip form back with something they can act on.
    it 'sends the visitor back to the form when OverDrive is unreachable' do
      stub_request(:get, HttpFixtures::FIND_LIBRARIES_URL).to_return(status: 403, body: '<html>Access Denied</html>')

      post_zip '94103'

      assert_equal '/search/shelves/to-read/overdrive', last_response.headers['location']
    end
  end

  describe 'POST /search/availability' do
    def post_consortium consortium
      stub_request(:get, HttpFixtures::REVIEW_LIST_URL).to_return(status: 200, body: HttpFixtures.goodreads_review_page([HttpFixtures.goodreads_review]))

      cached = {shelf_name: 'to-read', libraries: [%w[1135 Seattle]]}
      with_anonymous_session(cached) do
        get '/search/library'
        csrf = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
        post '/search/availability', 'consortium' => consortium, '_csrf' => csrf
      end
    end

    # The OverDrive check does not fit in a request (#1347), so the POST queues
    # it and hands the browser to the progress page, which waits on a socket.
    it 'queues the check and sends the browser to the progress page' do
      post_consortium '1135'

      assert_equal '/search/availability/progress', last_response.headers['location']
    end

    it 'rejects a library selection that is not a positive integer' do
      post_consortium 'not-a-library'

      assert_equal '/search/library', last_response.headers['location']
    end
  end
end
