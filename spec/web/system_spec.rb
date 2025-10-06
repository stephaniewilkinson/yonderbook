# frozen_string_literal: true

require_relative 'spec_helper'

describe App do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let :app do
    App
  end

  it 'responds to root' do
    get '/'
    assert last_response.ok?
    assert_includes last_response.body, 'Yonderbook'
  end

  it 'responds to /about' do
    get '/about'
    assert last_response.ok?
    assert_includes last_response.body, 'About'
  end

  it 'lets user log in and look at a shelf' do
    visit '/'
    # First login attempt - this will redirect to Goodreads
    first(:link, 'Log in with Goodreads').click
    click_on(class: 'authPortalSignInButton')
    fill_in 'ap_email', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'signInSubmit'
    sleep 2
    visit '/'
    first(:link, 'Log in with Goodreads').click
    click_on 'Shelves'
    assert_text 'Choose a shelf'
    all(:link, 'Stats')[2].click
    sleep 5
    assert_text 'Publication Years'
    click_on 'Shelves'
    assert_text 'to-read'
    first(:button, 'Get Books').click
    assert_text 'Choose a format'
    # Click eBooks link directly by visiting the overdrive path
    visit '/auth/shelves/to-read/overdrive'
    assert_text 'zip code'
    fill_in 'zipcode', with: '94103'
    click_on 'Find a library'
    assert_text 'Library'
    find('button[id="1683"]').click  # Click the library selection button by consortium ID
    sleep 5  # Wait for OverDrive API to respond
    assert_text 'Available'
    click_on 'Unavailable'
    sleep 1  # Wait for the unavailable books section to load
    assert_text 'Unavailable'  # Just verify we can see the unavailable section
    click_on 'Shelves'
    assert_text 'abandoned'
    all(:button, 'Get Books').find { |btn| btn.text == 'Get Books' }.click  # Click Get Books for abandoned shelf
    assert_text 'Choose a format'
    within('.fixed') do  # Within the modal
      find('a', text: 'By Mail').click
    end
    fill_in 'username', with: ENV.fetch('BOOKMOOCH_USERNAME')
    fill_in 'password', with: ENV.fetch('BOOKMOOCH_PASSWORD')
    click_button 'Authenticate'
    sleep 10  # Wait for BookMooch API to respond
    assert_text 'Success!'
  end
end
