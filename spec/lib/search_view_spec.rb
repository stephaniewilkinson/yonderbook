# frozen_string_literal: true

require_relative 'spec_helper'
require 'tilt'

AUTH_URL = 'https://www.goodreads.com/oauth/authorize?oauth_token=abc123'

OAUTH_ANCHOR = /<a[^>]*href=['"]#{Regexp.escape(AUTH_URL)}['"][^>]*>/

describe 'views/search.erb' do
  # Rendered through Tilt rather than a request: this is the view's own markup,
  # and the route that serves it belongs to #1267.
  def render_search auth_url = AUTH_URL
    scope = Object.new
    scope.instance_variable_set :@auth_url, auth_url
    Tilt.new('views/search.erb').render(scope)
  end

  # The anchor wrapping the OAuth URL, so assertions about it cannot accidentally
  # match one of the other links on the page.
  def oauth_anchor(html) = html[OAUTH_ANCHOR]

  it 'points the OAuth button at the authorize URL' do
    refute_nil oauth_anchor(render_search), 'no link to @auth_url'
  end

  # target="_blank" opens a tab Capybara does not follow, which is why the
  # anonymous flow specs in #1264 need this link to navigate in place.
  it 'keeps the OAuth link in the same tab' do
    refute_includes oauth_anchor(render_search).to_s, 'target'
  end

  it 'carries the Goodreads icon with the invert filter' do
    html = render_search

    assert_includes html, '/img/goodreads-icon.png'
    assert_includes html, 'brightness-0 invert'
  end

  it 'explains why connecting takes two clicks' do
    assert_match(/two clicks/i, render_search)
  end

  it 'lays out the three steps' do
    html = render_search

    assert_includes html, 'md:grid-cols-3'
    ['Connect', 'Pick Your Library', 'See Results'].each do |step|
      assert_includes html, step
    end
  end

  it 'keeps the stats bar from the marketing page' do
    html = render_search

    assert_includes html, 'Readers served'
    assert_includes html, 'Libraries searchable'
  end

  it 'offers the login route to people who already have an account' do
    assert_includes render_search, '/authenticate'
  end

  # Renders for a visitor whose request token could not be fetched -- Goodreads
  # being unreachable must not blank the homepage.
  it 'still renders without an auth url' do
    html = render_search nil

    refute_empty html
    assert_includes html, 'Pick Your Library'
  end
end
