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

    def title_with copies_available
      Result.new(
        'Sapiens',
        'Yuval Noah Harari',
        'cover.jpg',
        copies_available,
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

    it 'does not count results with nothing to borrow now' do
      assert_empty events_for_results([title_with(0)])
    end
  end

  it 'marks the library form so submitting it is reported' do
    html = File.read(File.expand_path('../../views/library.erb', __dir__))

    assert_includes html, 'data-fathom-submit="library_selected"'
  end
end
