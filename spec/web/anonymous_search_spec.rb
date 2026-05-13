# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Anonymous search flow' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  describe 'GET /search-callback' do
    it 'redirects to / with error when no request token is cached' do
      visit '/search-callback'
      assert_current_path '/'
    end
  end

  describe 'GET /search/shelves' do
    it 'redirects to / when no session credentials exist' do
      visit '/search/shelves'
      assert_current_path '/'
    end
  end
end
