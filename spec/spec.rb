# frozen_string_literal: true

require_relative 'spec_helper'

describe App do
  include Capybara::DSL
  include Rack::Test::Methods

  let :app do
    App
  end

  it 'responds to root' do
    get '/'
    assert last_response.ok?
    assert_includes last_response.body, 'Bookwyrm'
  end

  it 'responds to root' do
    get '/about'
    assert last_response.ok?
    assert_includes last_response.body, 'About'
  end

  it 'lets user log in and look at a shelf' do
    visit '/'
    click_on 'Log in with goodreads'
    fill_in 'Email Address', with: 'what.happens@gmail.com'
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'Sign in'
    assert_text 'Your Goodreads Bookshelves'
    click_on 'currently-reading'
    assert_text 'Receive books'
    fill_in 'username', with: 'swilk001'
    fill_in 'password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'Authenticate'
    assert_text 'Success'
    click_on 'Shelves'
    assert_text 'Your Goodreads Bookshelves'
    click_on 'financial-books'
    fill_in 'zipcode', with: '94103'
    click_on 'Find a library'
    assert_text 'Libraries'
  end
end
