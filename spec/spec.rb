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

  it 'responds to root' do
    get '/about'
    assert last_response.ok?
    assert_includes last_response.body, 'About'
  end

  it 'lets user log in and look at a shelf' do
    visit '/'
    click_on 'Log in with goodreads'
    fill_in 'Email Address', with: ENV.fetch('GOODREADS_EMAIL')
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'Sign in'
    assert_text 'to-read'
    ind("a[href='#modal-financial-books']").click
    assert_text 'financial-books'
    click_link 'eBooks'
    fill_in 'zipcode', with: '94103'
    click_on 'Find a library'
    assert_text 'Libraries'
    click_on '1683'
    assert_text 'Available Books'
    click_on 'Unavailable'
    assert_text 'The New Coffeehouse Investor'
    click_on 'Shelves'
    click_link 'didn-t-want-to-finish'
    click_link 'By Mail'
    fill_in 'username', with: ENV.fetch('BOOKMOOCH_USERNAME')
    fill_in 'password', with: ENV.fetch('BOOKMOOCH_PASSWORD')
    click_button 'Authenticate'
    assert_text 'Success!'
  end
end
