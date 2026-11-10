# frozen_string_literal: true

require_relative 'spec_helper'

# Claims the site made that were not true, removed before launch (gtm.md,
# "What blocks a launch"). Each one is pinned so it cannot quietly come back.
describe 'honest copy' do
  include Rack::Test::Methods

  let(:app) { App }

  def page_text path
    get path
    assert_equal 200, last_response.status, "#{path} did not render"
    last_response.body
  end

  PUBLIC_PAGES = %w[/ /about /how-it-works /faq].freeze

  # The author-gender chart is switched off (views/shelves/show.erb), so
  # nothing may advertise it.
  it 'advertises no author-gender or diversity analytics' do
    PUBLIC_PAGES.each do |path|
      body = page_text(path)

      refute_match(/author gender/i, body, "#{path} still advertises author gender")
      refute_match(/diversity/i, body, "#{path} still advertises diversity tracking")
    end
  end

  # Its source was a Universal Analytics tag that stopped collecting in 2023.
  it 'claims no reader count it cannot back up' do
    refute_includes page_text('/'), 'Readers served'
  end

  # Imported libraries are saved to the account; only API shelves are not.
  it 'does not say every shelf is fetched fresh from Goodreads' do
    refute_includes page_text('/faq'), 'fetched fresh'
  end

  # Searching several libraries and formats beyond ebooks have both shipped.
  it 'does not list shipped features as coming next' do
    refute_includes page_text('/about'), "I'm working on searching more than one library"
  end

  it 'lists every public page in the sitemap' do
    sitemap = page_text('/sitemap.xml')

    %w[/how-it-works /faq /about].each { |path| assert_includes sitemap, "https://yonderbook.com#{path}</loc>" }
  end

  # Since #1398 every book is searched by title, ISBN or not. A book with no
  # ISBN that was found used to be listed twice: in Available, and again under
  # "Could Not Match", blamed on the ISBN it does not need.
  describe 'a book Goodreads has no ISBN for' do
    Copy = Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)

    def results_for copies_owned
      book = Copy.new(
        'Piranesi',
        'Susanna Clarke',
        'cover.jpg',
        copies_owned.positive? ? 2 : 0,
        copies_owned,
        '',
        'https://link.overdrive.com/?content=9',
        'id-9',
        'ebook',
        'Seattle Public Library',
        true,
        '2024-01-01'
      )
      values = ANON_CREDENTIALS.merge(titles: [book], shelf_name: 'to-read', libraries: [%w[1135 Seattle]])
      Cache.stub(:get, ->(_session, key) { values[key] }) { page_text('/search/availability') }
    end

    it 'is listed once, as available, when the library has it' do
      body = results_for(3)

      assert_includes body, 'There are 1 books available'
      refute_includes body, 'Could Not Match'
      refute_includes body, 'Missing ISBN'
    end

    it 'is simply not owned when the library does not have it' do
      body = results_for(0)

      assert_includes Nokogiri::HTML(body).text, "1 books aren't owned by your library"
      refute_includes body, 'Missing ISBN'
    end
  end
end
