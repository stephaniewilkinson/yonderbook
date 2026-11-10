# frozen_string_literal: true

require_relative 'spec_helper'

# Messages set as flash[:error] were dropped after a redirect: the symbol key
# reached the next request still a symbol, and the partial only read
# flash['error']. Signed in, an unrecognised zip also went via /libraries,
# which redirected again and spent the message on the way.
describe 'messages after a redirect' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  it 'tells an anonymous visitor they left the zip code empty' do
    values = ANON_CREDENTIALS.merge(shelf_name: 'to-read')
    Cache.stub(:get, ->(_session, key) { values[key] }) do
      get '/search/shelves/to-read/overdrive'
      csrf = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
      post '/search/library', 'zipcode' => '', '_csrf' => csrf
      follow_redirect!
    end

    assert_includes Nokogiri::HTML(last_response.body).text, 'You need to enter a zip code'
  end

  it 'tells a signed-in reader a zip code was not recognised, on the zip form' do
    seed_goodreads_user
    visit '/goodreads/shelves/to-read/overdrive'
    fill_in 'zipcode', with: '00000'
    click_button 'Find a library'

    assert_current_path '/goodreads/shelves/to-read/overdrive'
    assert_text "We don't recognize that zip code"
  end

  # '/' sends a signed-in reader on to /home, and that hop spent the message.
  describe 'signed in, where the homepage would have bounced them' do
    def signed_in
      email, password = create_account_direct
      password_login email, password
    end

    it 'explains why the anonymous search sent them home' do
      signed_in
      visit '/search/shelves'

      assert_current_path '/home'
      assert_text 'Connect Goodreads or upload a CSV export to get started'
    end
  end
end
