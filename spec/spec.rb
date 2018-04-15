# frozen_string_literal: true

require_relative 'spec_helper'

include Rack::Test::Methods

describe App do
  include Capybara::DSL

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
  it 'can navigate to homepage' do
    visit '/'
    assert_text 'Bookwyrm'
  end
  it 'lets user log in' do
    visit '/'
    click_on 'Log in with goodreads'
    fill_in 'Email Address', with: 'what.happens@gmail.com'
    fill_in 'Password', with: ENV.fetch('GOODREADS_PASSWORD')
    click_on 'Sign in'
    assert_text 'Your Goodreads Bookshelves'
  end
end
