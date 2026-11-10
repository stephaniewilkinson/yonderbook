# frozen_string_literal: true

require_relative 'spec_helper'

# A shelf that is not cached yet is fetched in the background while the
# loading page polls, because fetching it inside the request ran past
# RequestTimeout's 25s on large shelves. These run in the browser, against
# Falcon, because the background fetch needs a fiber scheduler: under
# Rack::Test the routes fall back to fetching inline.
describe 'Shelf loading' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour

  # The loading page used to be rendered and then ignored -- `view` does not
  # halt -- so the route went on to get_gender(nil) and the page never showed.
  it 'loads an uncached shelf for the stats page' do
    seed_goodreads_user
    visit '/goodreads/shelves/to-read'

    assert_text 'Loading your'
    page.assert_text 'Publication Years', wait: 15
  end

  # The fetch is started by the request that renders the loading page, and has
  # to keep going after that response has been sent.
  it 'finishes a fetch that outlives the request that started it' do
    page_body = HttpFixtures.goodreads_review_page([HttpFixtures.goodreads_review])
    stub_request(:get, %r{\Ahttps://www\.goodreads\.com/review/list/}).to_return do
      sleep 3
      {status: 200, body: page_body}
    end
    seed_goodreads_user
    visit '/goodreads/shelves/to-read'

    assert_text 'Loading your'
    page.assert_text 'Publication Years', wait: 15
  end

  it 'loads an uncached shelf for the BookMooch page instead of fetching it inline' do
    seed_goodreads_user
    visit '/goodreads/shelves/to-read/bookmooch'

    assert_text 'Loading your'
    page.assert_text 'new books to add', wait: 15
    assert_current_path '/goodreads/shelves/to-read/bookmooch'
  end

  # A failed fetch still marks itself ready, and the loading page reloaded into
  # itself forever because nothing read the error.
  it 'says so and stops loading when Goodreads fails' do
    stub_request(:get, %r{\Ahttps://www\.goodreads\.com/review/list/}).to_return(status: 503, body: 'down')
    seed_goodreads_user
    visit '/goodreads/shelves/to-read'

    page.assert_text 'We could not load that shelf from Goodreads', wait: 15
    assert_current_path '/goodreads/shelves'
  end

  # The availability check needs the whole shelf. The zip code form starts it
  # loading in the background; picking libraries before it is in waits on the
  # loading page, then carries on with the libraries already chosen, instead
  # of fetching inside the request and timing out.
  it 'waits for a slow shelf after libraries are picked, then runs the check' do
    page_body = HttpFixtures.goodreads_review_page([HttpFixtures.goodreads_review])
    stub_request(:get, %r{\Ahttps://www\.goodreads\.com/review/list/}).to_return do
      sleep 6
      {status: 200, body: page_body}
    end
    stub_request(:get, HttpFixtures::FIND_LIBRARIES_URL).to_return(status: 200, body: JSON.dump([HttpFixtures.overdrive_library]))
    seed_goodreads_user

    visit '/goodreads/shelves/to-read/overdrive'
    fill_in 'zipcode', with: '98101'
    click_button 'Find a library'
    find('.library-choice', match: :first).check
    click_button 'Check availability'

    assert_text 'Loading your'
    assert_current_path '/goodreads/shelves/to-read/overdrive/continue'
    assert_current_path '/goodreads/availability/progress', wait: 20
  end
end
