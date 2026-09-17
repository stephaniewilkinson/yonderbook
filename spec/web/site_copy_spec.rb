# frozen_string_literal: true

require_relative 'spec_helper'
require 'json'

# Copy that appears twice used to be typed twice. These specs fail if the two
# renderings drift apart again, which is the failure mode that made the FAQ,
# the HowTo steps and the stats bar worth centralising in the first place.
describe 'site copy' do
  # Rack::Test for the markup assertions; Capybara for the one case that needs
  # a real login, since the logged-out nav is what an unauthenticated
  # Rack::Test request would always see.
  include Capybara::DSL
  include Minitest::Capybara::Behaviour
  include Rack::Test::Methods

  let(:app) { App }

  def json_ld_of type
    get(yield) if block_given?
    blocks = last_response.body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
    blocks.map { |raw| JSON.parse raw }.find { |doc| doc['@type'] == type }
  end

  describe 'FAQ' do
    before { get '/faq' }

    it 'renders every answer in the visible page' do
      SiteCopy::FAQ.each do |entry|
        assert_includes last_response.body, entry[:question]
        assert_includes last_response.body, entry[:answer]
      end
    end

    it 'publishes the same answers as FAQPage structured data' do
      # Google treats JSON-LD that does not match visible content as a markup
      # violation, and these answers lived in two places for a while.
      faq = json_ld_of 'FAQPage'

      pairs = faq['mainEntity'].map { |q| [q['name'], q['acceptedAnswer']['text']] }

      assert_equal SiteCopy::FAQ.map { |entry| [entry[:question], entry[:answer]] }, pairs
    end
  end

  describe 'HowTo' do
    before { get '/how-it-works' }

    it 'lists the steps in the order the app walks people through' do
      # The schema used to put "select your library" before "choose a shelf".
      # You cannot pick a library before picking a shelf: the zip code form
      # lives under the shelf path.
      steps = json_ld_of('HowTo')['step']

      assert_equal(SiteCopy::STEPS.map { |step| step[:name] }, steps.map { |step| step['name'] })
      assert_equal((1..SiteCopy::STEPS.size).to_a, steps.map { |step| step['position'] })
    end

    it 'gives each step its own url' do
      # Two steps used to share a URL, one of which pointed at the wrong page.
      urls = json_ld_of('HowTo')['step'].filter_map { |step| step['url'] }

      assert_equal urls.uniq.size, urls.size
    end

    it 'renders the same steps visibly' do
      SiteCopy::STEPS.each { |step| assert_includes last_response.body, step[:name] }
    end
  end

  describe 'price claims' do
    it 'does not assert a machine-readable price site-wide' do
      # `"price": "0"` shipped in the WebApplication JSON-LD on every page.
      # Google caches rich results well after the page behind them changes,
      # so the claim outlived any edit. The FAQ still says it in words.
      %w[/ /faq /about /how-it-works].each do |path|
        get path

        refute json_ld_of('WebApplication').key?('offers'), "#{path} still advertises a price"
      end
    end

    it 'still says it is free where a person can read it' do
      get '/faq'

      assert_includes last_response.body, 'Yonderbook is free to use'
    end
  end

  describe 'stats bar' do
    it 'derives years running rather than hardcoding it' do
      # "10" sat next to "Since 2016": right in 2026, wrong in 2027, and
      # nothing would have caught it.
      assert_equal Time.now.year - SiteCopy::LAUNCH_YEAR, SiteCopy.years_running

      years = SiteCopy.stats.find { |stat| stat[:label] == 'Years running' }

      assert_equal SiteCopy.years_running.to_s, years[:figure]
    end

    it 'records where every figure came from' do
      SiteCopy::STATS.each do |stat|
        refute_empty stat[:source].to_s, "#{stat[:label]} has no recorded source"
      end
    end

    it 'renders one bar from one partial on the homepage' do
      get '/'

      SiteCopy.stats.each { |stat| assert_includes last_response.body, stat[:label] }
    end
  end

  describe 'the two-click explanation' do
    it 'says what each click does, not just that there are two' do
      # /connect redirects straight to Goodreads; the homepage is where an
      # anonymous visitor reads this.
      get '/'

      assert_includes last_response.body, SiteCopy::TWO_CLICK_BODY
    end

    it 'offers the CSV import wherever the double-click is mentioned' do
      # The CSV import is the one piece of information that removes the
      # problem rather than excusing it, and only one of the four former
      # wordings mentioned it.
      get '/'

      assert_includes last_response.body, SiteCopy::TWO_CLICK_ALTERNATIVE_LINK
      assert_includes last_response.body, 'href="/import"'
    end
  end

  describe 'account-required copy' do
    it 'does not tell anonymous visitors to create an account first' do
      # The anonymous flow lets someone connect Goodreads and get results
      # without an account. The marketing copy said the opposite.
      get '/how-it-works'

      refute_includes last_response.body, 'Create a Yonderbook account'
      assert_includes last_response.body, 'No account needed'
    end
  end

  describe 'robots directives' do
    it 'leaves the static pages indexable' do
      %w[/ /faq /about /how-it-works].each do |path|
        get path

        refute_includes last_response.body, 'name="robots"', "#{path} asks not to be indexed"
      end
    end

    it 'asks search engines not to index one visitor\'s results' do
      # A set of availability results belongs to one person and one moment.
      # Same for the progress page, which exists only while a job runs.
      %w[availability availability_progress].each do |view|
        source = File.read("views/#{view}.erb")

        assert_includes source, "content_for :robots, 'noindex'"
      end
    end
  end

  # #1271. The nav already branched on login state; what it never had was a way
  # out. /logout was reachable only by typing the URL.
  describe 'navigation' do
    it 'offers an anonymous visitor the way in' do
      get '/'

      assert_includes last_response.body, 'href="/authenticate"'
      assert_includes last_response.body, 'href="/sign-up"'
      refute_includes last_response.body, 'href="/logout"'
    end

    it 'offers a logged-in user the way out' do
      email, password = create_account_direct
      password_login(email, password)
      assert_text 'Welcome back,'

      assert page.has_link?('Log Out', href: '/logout'), 'no way to log out from the nav'
    end

    it 'links the FAQ from somewhere on every page' do
      %w[/ /about /how-it-works].each do |path|
        get path

        assert_includes last_response.body, 'href="/faq"', "#{path} does not link the FAQ"
      end
    end
  end
end
