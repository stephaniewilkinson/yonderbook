# frozen_string_literal: true

require_relative 'spec_helper'

# The availability results page: what it renders once a check has finished.
# Split from anonymous_search_flow_spec.rb, which covers getting there.
#
# The same view serves the authenticated page, so the conversion copy that
# belongs only to anonymous visitors is asserted absent there too.
describe 'availability results' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  def with_anonymous_session(cached = {}, &)
    values = ANON_CREDENTIALS.merge(cached)
    Cache.stub(:get, ->(_session, key) { values[key] }, &)
  end

  describe 'GET /search/availability with results' do
    Title = Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)

    def available_title
      Title.new(
        'Sapiens',
        'Yuval Noah Harari',
        'cover.jpg',
        3,
        5,
        '9780062316097',
        'https://link.overdrive.com/?content=1',
        'id-1',
        'ebook',
        'Seattle Public Library',
        false,
        '2024-01-01'
      )
    end

    def render_results(&)
      with_anonymous_session(titles: [available_title], shelf_name: 'to-read', libraries: [%w[1135 Seattle]], &)
    end

    it 'renders the results' do
      render_results do
        get '/search/availability'

        assert_equal 200, last_response.status
        assert_includes last_response.body, 'Sapiens'
      end
    end

    # #1268. The prompt comes after the results, because the product has to
    # have worked before it asks for anything.
    it 'offers an account, saying what one is for' do
      render_results do
        get '/search/availability'

        assert_includes last_response.body, 'Want to keep these results?'
        assert_includes last_response.body, 'Create a free account'
        assert_includes last_response.body, 'BookMooch'
      end
    end

    it 'teases the reading analytics' do
      render_results do
        get '/search/availability'

        assert_includes last_response.body, 'See your reading patterns'
      end
    end

    # #1273. A set of results belongs to one visitor and one moment.
    it 'asks not to be indexed' do
      render_results do
        get '/search/availability'

        assert_includes last_response.body, 'name="robots"'
        assert_includes last_response.body, 'noindex'
      end
    end
  end

  # Case 11: the same view serves the authenticated flow, where none of the
  # conversion copy belongs. @anonymous_search is what separates them, and it
  # is set on the anonymous route only.
  describe 'the authenticated availability page' do
    it 'shows no signup prompt' do
      email, password = create_account_direct
      account = DB[:accounts].where(email: email).first
      add_goodreads_connection(account[:id], '1', 'token', 'secret')
      password_login(email, password)
      assert_text 'Welcome back,'

      Cache.stub(:get, ->(_session, key) { key == :titles ? [available_title_for_authenticated] : nil }) do
        visit '/goodreads/availability'

        refute_includes page.text, 'Want to keep these results?'
        refute_includes page.text, 'See your reading patterns'
      end
    end

    def available_title_for_authenticated
      Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)
        .new('Sapiens',
             'Yuval Noah Harari',
             'cover.jpg',
             3,
             5,
             '9780062316097',
             'https://link.overdrive.com/',
             'id-1',
             'ebook',
             'Seattle Public Library',
             false,
             '2024-01-01')
    end
  end

  # #441. collection_token, website_id and library_url all came off one
  # Overdrive instance and were three session keys representing one object --
  # and two of the three were written, read back, assigned to ivars, and used
  # by nothing at all.
  describe 'the library context on the results page' do
    def render_with library_url
      cached = {titles: [flow_title], library_url: library_url, shelf_name: 'to-read', libraries: [%w[1135 Seattle]]}
      with_anonymous_session(cached) { get '/search/availability' }
    end

    def flow_title
      Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)
        .new('Unowned Book', 'An Author', 'cover.jpg', 0, 0, '9780062316097', nil, nil, 'ebook', 'Seattle Public Library', false, '2024-01-01')
    end

    it 'links the library using the cached url' do
      render_with 'https://link.overdrive.com/?websiteID=87'

      assert_includes last_response.body, 'https://link.overdrive.com/?websiteID=87'
    end

    it 'falls back to the OverDrive library finder when the url is unknown' do
      # Not every consortium returns a dlrHomepage link. The view used to
      # rebuild the URL from a website id, so a missing one rendered
      # "?websiteID=" with nothing after it -- a link to nowhere.
      render_with nil

      assert_includes last_response.body, AvailabilityHelpers::OVERDRIVE_HOME
      refute_includes last_response.body, 'websiteID="'
    end
  end

  # #542. Every result used to be labelled "Read" whatever the library holds.
  describe 'format on the results page' do
    def render_titles titles
      cached = {titles: titles, library_url: 'https://link.overdrive.com/?websiteID=87', shelf_name: 'to-read', libraries: [%w[1135 Seattle]]}
      with_anonymous_session(cached) { get '/search/availability' }
    end

    def title_of format, copies_available: 3
      Title.new(
        'Sapiens',
        'Yuval Noah Harari',
        'cover.jpg',
        copies_available,
        5,
        '9780062316097',
        'https://link.overdrive.com/?c=1',
        'id-1',
        format,
        'Seattle Public Library',
        false,
        '2024-01-01'
      )
    end

    it 'says Listen for an audiobook' do
      render_titles [title_of('audiobook')]

      assert_includes last_response.body, 'Listen'
      refute_includes last_response.body, '>Read<'
    end

    it 'says Read for an ebook' do
      render_titles [title_of('ebook')]

      assert_includes last_response.body, 'Read'
    end

    it 'names the format on the copy itself, next to the library' do
      # A book-level badge cannot work once a book can have two formats. The
      # format belongs to the copy, beside the library holding it.
      render_titles [title_of('audiobook')]

      assert_match(%r{Seattle Public Library</span>\s*·\s*audiobook}, last_response.body)
    end

    it 'shows both formats of the same book as separate results' do
      render_titles [title_of('ebook'), title_of('audiobook')]

      assert_includes last_response.body, 'Listen'
      assert_includes last_response.body, 'ebook'
      assert_includes last_response.body, 'audiobook'
    end
  end

  # The action has to match what the copy actually is.
  describe 'the action on a copy' do
    def render_format format
      title = Title.new(
        'Sapiens',
        'Yuval Noah Harari',
        'cover.jpg',
        3,
        5,
        '9780062316097',
        'https://link.overdrive.com/?c=1',
        'id-1',
        format,
        'Seattle Public Library',
        false,
        '2024-01-01'
      )
      cached = {titles: [title], library_url: 'https://link.overdrive.com/?websiteID=87', shelf_name: 'to-read', libraries: [%w[1135 Seattle]]}
      with_anonymous_session(cached) { get '/search/availability' }
    end

    it 'says Listen for an audiobook' do
      render_format 'audiobook'

      assert_includes last_response.body, 'Listen'
    end

    it 'says Watch for a video' do
      render_format 'video'

      assert_includes last_response.body, 'Watch'
    end

    it 'says Read for anything textual, including a format it has not seen' do
      render_format 'magazine'

      assert_includes last_response.body, 'Read'
      assert_includes last_response.body, 'magazine'
    end
  end
end
