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
    visit '/auth/shelves'
    click_on 'Log in with goodreads'
    click_on(class: 'authPortalSignInButton')
    fill_in 'ap_email', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'signInSubmit'
    find("a[href='shelves/homesteading']").click
    assert_text 'Publication years'
    click_on 'Shelves'
    assert_text 'to-read'
    find("a[href='#modal-zora']").click
    assert_text 'format'
    # click_link 'eBooks'
    # fill_in 'zipcode', with: '94103'
    # click_on 'Find a library'
    # assert_text 'Library'
    # click_on '1683'
    # assert_text 'available'
    # click_on 'Unavailable'
    # assert_text 'The New Coffeehouse Investor'
    # click_on 'Shelves'
    # find("a[href='#modal-abandoned']").click
    # sleep 1
    click_link 'By Mail'
    fill_in 'username', with: ENV.fetch('BOOKMOOCH_USERNAME')
    fill_in 'password', with: ENV.fetch('BOOKMOOCH_PASSWORD')
    click_button 'Authenticate'
    assert_text 'Success!'
  end
end
