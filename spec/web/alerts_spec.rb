# frozen_string_literal: true

require_relative 'spec_helper'

# #1422. Turning availability alerts on and off, and the cron's endpoint.
describe 'availability alerts' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  Copy = Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)

  def waiting_copy
    Copy.new(
      'Piranesi',
      'Susanna Clarke',
      'c.jpg',
      0,
      2,
      '9781635575996',
      'https://seattle.overdrive.com/media/1',
      'ABC-1',
      'ebook-overdrive',
      'Seattle',
      false,
      '2024-01-01'
    )
  end

  def signed_in_reader
    email, password = create_account_direct
    id = DB[:accounts].where(email:).get(:id)
    add_goodreads_connection id, '42', 'token', 'secret'
    password_login email, password
    id
  end

  def with_results(&)
    values = {
      titles: [waiting_copy],
      availability_libraries: [%w[1135 Seattle]],
      library_names: %w[Seattle],
      shelf_name: 'to-read',
      availability_book_info: [{title: 'Piranesi', author: 'Susanna Clarke', isbn: '9781635575996'}, {title: 'Not at the library', author: 'X', isbn: nil}]
    }
    Cache.stub(:get, ->(_session, key) { values[key] }, &)
  end

  describe 'POST /alerts/check' do
    def with_token value
      previous = ENV.fetch('ALERTS_TOKEN', nil)
      ENV['ALERTS_TOKEN'] = value
      yield
    ensure
      ENV['ALERTS_TOKEN'] = previous
    end

    it 'is not found without the token' do
      with_token('right') { post '/alerts/check' }

      assert_equal 404, last_response.status
    end

    it 'is not found with the wrong token' do
      with_token('right') { post '/alerts/check', {}, 'HTTP_AUTHORIZATION' => 'Bearer wrong' }

      assert_equal 404, last_response.status
    end

    it 'is not found when no token is configured, even if one is sent' do
      with_token('') { post '/alerts/check', {}, 'HTTP_AUTHORIZATION' => 'Bearer ' }

      assert_equal 404, last_response.status
    end

    it 'runs the check with the right token' do
      ran = false
      AvailabilityAlerts.stub(:run_due, -> { ran = true }) do
        with_token('right') { post '/alerts/check', {}, 'HTTP_AUTHORIZATION' => 'Bearer right' }
      end

      assert_equal 202, last_response.status
      assert ran
    end
  end

  it 'turns on from the results page and says what it is watching' do
    id = signed_in_reader
    with_results do
      visit '/goodreads/availability'
      click_button 'alerts-on'

      assert_text "Alerts are on. We'll email you"
      assert_text 'Every morning we check 1 copy at Seattle'
    end

    assert_equal ['abc-1'], DB[:watched_titles].where(user_id: id).select_map(:reserve_id)
    assert_equal ['Not at the library'], DB[:wanted_books].where(user_id: id).select_map(:title)
    assert_includes page.html, '<meta name="fathom-event" content="notify_subscribed">'
  end

  it 'turns off from the account page and deletes what it watched' do
    id = signed_in_reader
    AvailabilityAlerts.subscribe id, titles: [waiting_copy], libraries: [%w[1135 Seattle]]
    visit '/account'
    assert_text 'Availability alerts are on'
    click_button 'Turn off alerts'

    assert_text 'Alerts are off'
    assert_equal 0, DB[:alert_subscriptions].where(user_id: id).count
    assert_equal 0, DB[:watched_titles].where(user_id: id).count
  end

  describe 'the unsubscribe link in an email' do
    def subscribed_token
      email, = create_account_direct
      id = DB[:accounts].where(email:).get(:id)
      AvailabilityAlerts.subscribe id, titles: [waiting_copy], libraries: [%w[1135 Seattle]]
      [id, DB[:alert_subscriptions].where(user_id: id).get(:unsubscribe_token)]
    end

    # Mail scanners open links; opening it must not unsubscribe anyone.
    it 'only asks when opened' do
      id, token = subscribed_token
      visit "/alerts/unsubscribe/#{token}"

      assert_button 'Turn off alerts'
      assert_equal 1, DB[:alert_subscriptions].where(user_id: id).count
    end

    it 'turns alerts off without signing in' do
      id, token = subscribed_token
      visit "/alerts/unsubscribe/#{token}"
      click_button 'alerts-unsubscribe'

      assert_text "You won't get any more of these emails"
      assert_equal 0, DB[:alert_subscriptions].where(user_id: id).count
    end

    it "accepts a mail app's one-click unsubscribe" do
      id, token = subscribed_token
      post "/alerts/unsubscribe/#{token}"

      assert_equal 200, last_response.status
      assert_equal 0, DB[:alert_subscriptions].where(user_id: id).count
    end
  end
end
