# frozen_string_literal: true

require_relative 'spec_helper'
require 'json'

describe 'Nearest zip lookup' do
  include Rack::Test::Methods

  let :app do
    App
  end

  def lookup lat, lon
    get "/nearest-zip?lat=#{lat}&lon=#{lon}"
    JSON.parse last_response.body
  end

  it 'resolves coordinates to a nearby zip' do
    assert_equal 'CA', lookup(34.0901, -118.4065)['state']
  end

  it 'returns a zip the library form can submit' do
    assert_match(/\A\d{5}\z/, lookup(34.0901, -118.4065)['zip'])
  end

  it 'names the place so the user can sanity check it' do
    assert_equal 'Beverly Hills', lookup(34.0901, -118.4065)['city']
  end

  it 'answers with JSON' do
    get '/nearest-zip?lat=34.0901&lon=-118.4065'

    assert_includes last_response.headers.values.join(' '), 'application/json'
  end

  # Someone in London must not be told they live in Maine.
  it 'reports no match well outside the United States' do
    assert_equal 'no_match', lookup(51.5074, -0.1278)['error']
  end

  it 'reports no match rather than erroring on unparseable input' do
    get '/nearest-zip?lat=banana&lon=split'

    assert_equal 200, last_response.status
  end

  it 'reports no match when the parameters are missing entirely' do
    get '/nearest-zip'

    assert_equal 'no_match', JSON.parse(last_response.body)['error']
  end
end
