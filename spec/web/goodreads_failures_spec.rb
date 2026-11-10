# frozen_string_literal: true

require_relative 'spec_helper'

# Goodreads failing used to fall through to the catch-all, which sent the
# reader to the homepage with no word of why, and an empty shelf was blamed on
# Goodreads or checked anyway. Both now say what happened.
describe 'when Goodreads lets the reader down' do
  include Rack::Test::Methods

  let(:app) { App }

  def with_anonymous_session(cached = {}, &)
    values = ANON_CREDENTIALS.merge(cached)
    Cache.stub(:get, ->(_session, key) { values[key] }, &)
  end

  def landed_page
    follow_redirect!
    last_response.body
  end

  def text_of(html) = Nokogiri::HTML(html).text

  it "says Goodreads didn't answer, and offers the CSV import" do
    stub_request(:get, HttpFixtures::REVIEW_LIST_URL).to_return(status: 503, body: 'Service Unavailable')

    with_anonymous_session(shelf_name: 'to-read') { get '/search/shelves/to-read' }

    assert_equal '/import', URI(last_response.location).path
    html = landed_page
    assert_includes text_of(html), "Goodreads didn't answer"
    assert_includes html, '<meta name="fathom-event" content="goodreads_unreachable">'
  end

  it 'says the connection may have expired when Goodreads refuses it' do
    stub_request(:get, HttpFixtures::REVIEW_LIST_URL).to_return(status: 401, body: 'Unauthorized')

    with_anonymous_session(shelf_name: 'to-read') { get '/search/shelves/to-read' }

    assert_includes text_of(landed_page), 'It may have expired'
  end

  it 'says a shelf is empty, rather than blaming Goodreads or checking nothing' do
    stub_request(:get, HttpFixtures::REVIEW_LIST_URL).to_return(status: 200, body: HttpFixtures.goodreads_review_page([]))

    with_anonymous_session(shelf_name: 'to-read', libraries: [%w[1135 Seattle]]) do
      get '/search/library'
      csrf = last_response.body[/name="_csrf" value="([^"]+)"/, 1]
      post '/search/availability', 'consortium' => '1135', '_csrf' => csrf

      assert_equal '/search/shelves', URI(last_response.location).path
      Goodreads.stub(:fetch_shelves, [['to-read', 0]]) do
        assert_includes text_of(landed_page), 'Your to-read shelf has no books on it yet'
      end
    end
  end
end
