# frozen_string_literal: true

require_relative 'spec_helper'
require 'json'

describe 'Libby URL endpoint' do
  include Rack::Test::Methods

  let :app do
    App
  end

  def body_for query
    get "/api/libby_url?#{query}"
    JSON.parse last_response.body
  end

  it 'returns a search URL for a title' do
    assert_equal 'https://www.overdrive.com/search?q=Piranesi', body_for('title=Piranesi')['url']
  end

  it 'includes the author when given one' do
    assert_includes body_for('title=Piranesi&author=Susanna+Clarke')['url'], 'Susanna+Clarke'
  end

  it 'works without an author, which the caller may not have' do
    refute_nil body_for('title=Piranesi')['url']
  end

  it 'explains itself when the title is missing' do
    assert_equal 'title is required', body_for('')['error']
  end

  it 'answers with JSON' do
    get '/api/libby_url?title=Piranesi'

    assert_includes last_response.headers.values.join(' '), 'application/json'
  end

  it 'does not require authentication, since a bot calls it' do
    get '/api/libby_url?title=Piranesi'

    assert_equal 200, last_response.status
  end
end
