# frozen_string_literal: true

require_relative 'spec_helper'
require 'tilt'

# The page links to /connect rather than a pre-fetched authorize URL: building
# one at `/` would write to the session before the session id exists. See the
# comment in the view.
CONNECT_ANCHOR = %r{<a[^>]*href=['"]/connect['"][^>]*>}

describe 'views/search.erb' do
  # Rendered through Tilt rather than a request: this is the view's own markup,
  # and the route that serves it belongs to #1267.
  def render_search = Tilt.new('views/search.erb').render(Object.new)

  # The anchor wrapping the connect link, so assertions about it cannot
  # accidentally match one of the other links on the page.
  def connect_anchor(html) = html[CONNECT_ANCHOR]

  it 'points the Goodreads button at the connect route' do
    refute_nil connect_anchor(render_search), 'no link to /connect'
  end

  # target="_blank" opens a tab Capybara does not follow, which is why the
  # anonymous flow specs in #1264 need these links to navigate in place.
  it 'keeps every link in the same tab' do
    refute_includes render_search, '_blank'
  end

  # Nothing here may depend on an ivar: `/` renders this without fetching a
  # request token, so the page has to be complete on its own.
  it 'renders with no instance variables set at all' do
    html = render_search

    refute_nil connect_anchor(html)
    assert_includes html, 'Pick Your Library'
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
end
