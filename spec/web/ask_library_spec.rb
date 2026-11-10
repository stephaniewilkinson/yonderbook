# frozen_string_literal: true

require_relative 'spec_helper'

# The Unavailable tab asks the library to buy a book nobody owns, where the
# library's OverDrive site lets readers recommend titles.
describe 'asking a library to buy a book' do
  include Rack::Test::Methods

  let(:app) { App }

  Unowned = Struct.new(:title, :author, :image, :copies_available, :copies_owned, :isbn, :url, :id, :format, :library, :no_isbn, :date_added)

  def unavailable_results extra = {}
    book = Unowned.new('Piranesi', 'Susanna Clarke', 'c.jpg', 0, 0, '9781635575996', nil, nil, 'ebook', 'Seattle', false, '2024-01-01')
    values = ANON_CREDENTIALS.merge(titles: [book], shelf_name: 'to-read', libraries: [%w[1135 Seattle]], library_names: %w[Seattle]).merge(extra)
    Cache.stub(:get, ->(_session, key) { values[key] }) { get '/search/availability' }
    Nokogiri::HTML(last_response.body)
  end

  it "links to the library's own search for titles it could buy, and reports the click" do
    page = unavailable_results(library_site: 'https://spl.overdrive.com', library_site_name: 'Seattle')
    link = page.at_css('a[data-fathom-click="suggest_purchase_click"]')

    refute_nil link
    assert_equal 'Ask your library to buy it', link.text.strip
    assert_equal 'https://spl.overdrive.com/search?query=Piranesi+Susanna+Clarke&showAlternatives=true', link['href']
    assert_includes page.text, 'sign in with your library card'
  end

  it 'falls back to a library search when the library has no site of its own' do
    page = unavailable_results

    assert_nil page.at_css('a[data-fathom-click="suggest_purchase_click"]')
    assert_includes page.text, 'Search library'
  end
end
