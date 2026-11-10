# frozen_string_literal: true

require_relative 'spec_helper'

# #1408. Funnel events for Fathom's weekly email. The script that sends them
# only loads in production, so these assert what the page asks to be sent:
# a <meta name="fathom-event"> per event, or a data-fathom-submit on a form.
describe 'Fathom funnel events' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  def events_in html
    Nokogiri::HTML(html).css('meta[name="fathom-event"]').map { |meta| meta['content'] }
  end

  def page_events
    events_in page.html
  end

  it 'serves the script that sends them' do
    get '/js/fathom-events.js'

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'trackEvent'
  end

  it 'reports a sign-up once, on the page after the account is created' do
    visit '/sign-up'
    fill_in 'Email', with: "test_fathom_#{SecureRandom.hex(6)}@example.com"
    fill_in 'Password', with: 'SecurePassword123!'
    click_button 'Create Account'

    assert_text 'Check Your Email'
    assert_equal %w[signup], page_events

    visit '/check-email'

    assert_empty page_events, 'a reload is not a second sign-up'
  end

  it 'reports no sign-up when nobody just signed up' do
    visit '/check-email'

    assert_empty page_events
  end

  it 'reports a CSV import alongside the shelves it lands on' do
    email, password = create_account_direct
    password_login email, password
    visit '/import'
    attach_file 'library', File.expand_path('../fixtures/goodreads_export.csv', __dir__)
    click_button 'import-submit'

    assert_current_path '/goodreads/shelves'
    assert_equal %w[shelves_listed csv_uploaded], page_events
  end

  describe 'results' do
    Result = Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)

    def title_with copies_available, id: 'id-1'
      Result.new(
        "Book #{id}",
        'Yuval Noah Harari',
        'cover.jpg',
        copies_available,
        5,
        id == 'id-1' ? '9780062316097' : '9780141033570',
        'https://link.overdrive.com/?content=1',
        id,
        'ebook',
        'Seattle Public Library',
        false,
        '2024-01-01'
      )
    end

    def events_for_results titles
      values = ANON_CREDENTIALS.merge(titles: titles, shelf_name: 'to-read', libraries: [%w[1135 Seattle]])
      Cache.stub(:get, ->(_session, key) { values[key] }) do
        get '/search/availability'
        events_in last_response.body
      end
    end

    it 'reports the north star when a book can be borrowed now' do
      assert_equal %w[results_viewed], events_for_results([title_with(3)])
    end

    it 'reports empty results separately, for the hit rate' do
      assert_equal %w[results_empty], events_for_results([title_with(0)])
    end

    # #1411. The click out to OverDrive is the north star.
    it 'marks borrow and hold buttons with their own events' do
      values = ANON_CREDENTIALS.merge(titles: [title_with(3), title_with(0, id: 'id-2')], shelf_name: 'to-read', libraries: [%w[1135 Seattle]])
      Cache.stub(:get, ->(_session, key) { values[key] }) do
        get '/search/availability'
      end
      clicks = Nokogiri::HTML(last_response.body).css('[data-fathom-click]').map { |a| a['data-fathom-click'] }

      assert_includes clicks, 'borrow_clicked'
      assert_includes clicks, 'hold_clicked'
    end
  end

  # The logged-in Connect button links straight to goodreads.com, not /connect,
  # so the script's /connect click rule never sees it. #1411
  it 'marks the logged-in Connect button' do
    html = File.read(File.expand_path('../../views/connect_goodreads.erb', __dir__))

    assert_includes html, 'data-fathom-click="connect_started"'
    assert_includes File.read(File.expand_path('../../assets/js/fathom-events.js', __dir__)), 'data-fathom-click'
  end

  describe 'the Goodreads "one more time" failure' do
    def failing_goodreads(&)
      Goodreads.stub(:exchange_token, ->(_token) { raise OAuth::Unauthorized }) do
        Goodreads.stub(:fetch_user, ->(*) { raise OAuth::Unauthorized }) do
          token = Struct.new(:authorize_url).new('https://www.goodreads.com/oauth/authorize?oauth_token=t')
          Cache.stub(:get, ->(_session, key) { token if key == :request_token }, &)
        end
      end
    end

    it 'reports a retry for an anonymous visitor' do
      failing_goodreads { visit '/search-callback' }

      assert_text 'one more time'
      assert_includes page_events, 'connect_retry'
    end

    # It used to redirect to '/', which bounces a logged-in user on to /home
    # and spent the flash on the way, so the message never showed.
    it 'shows the message and reports a retry for a logged-in user' do
      email, password = create_account_direct
      password_login email, password
      failing_goodreads { visit '/login' }

      assert_current_path '/goodreads'
      assert_text 'one more time'
      assert_includes page_events, 'connect_retry'
    end
  end

  it 'reports a verified account, which signup alone cannot tell apart' do
    email = "test_fathom_#{SecureRandom.hex(6)}@example.com"
    visit '/sign-up'
    fill_in 'Email', with: email
    fill_in 'Password', with: 'SecurePassword123!'
    click_button 'Create Account'
    assert_text 'Check Your Email'

    account = DB[:accounts].where(email: email).first
    key = DB[:account_verification_keys].where(id: account[:id]).get(:key)
    visit "/verify-account?key=#{account[:id]}_#{key}"
    click_button 'Verify Account'

    assert_text 'Welcome back,'
    assert_includes page_events, 'account_verified'
  end

  it 'marks the library form so submitting it is reported' do
    html = File.read(File.expand_path('../../views/library.erb', __dir__))

    assert_includes html, 'data-fathom-submit="library_selected"'
  end
end
