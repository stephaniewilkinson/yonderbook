# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'dotenv/load'
require 'falcon/capybara'
require 'logger'
require 'minitest/autorun'
require 'minitest/capybara'
require 'minitest/pride'
require 'minitest/retry'
require 'rack/test'
require 'selenium-webdriver'
# Blocks the network, allowing localhost so Capybara's Falcon server and
# Selenium's driver connection still work.
#
# Note the limit of this: WebMock intercepts in-process HTTP only. When
# system_spec drives a real browser to goodreads.com, that traffic belongs to
# the browser process and is neither blocked nor stubbable from here.
require_relative '../support/http_mocking'

# Retry ONLY driver and network timeouts, and only twice. See issue #1329.
#
# spec/web/system_spec.rb drives a real browser through goodreads.com and
# Amazon's sign-in portal, with fixed sleeps and a loop to get past Amazon's
# CVF challenge. When the runner is slow or Amazon presents a challenge,
# Selenium's HTTP connection times out and the run fails for reasons that have
# nothing to do with this codebase -- roughly a third of main's runs. Since
# autoDeployTrigger is checksPass, that blocks production deploys until someone
# re-runs the job by hand.
#
# The list is deliberately narrow. Minitest::Assertion is absent, so a genuine
# bug still fails on the first attempt, and Capybara::ElementNotFound is absent
# because that is usually a real defect -- it is how the button-label bug in
# the import specs was caught. Retrying either would hide work, not save it.
RETRIED_ERRORS = [Net::ReadTimeout, Net::OpenTimeout, Selenium::WebDriver::Error::TimeoutError].freeze
Minitest::Retry.use! retry_count: 2, verbose: true, exceptions_to_retry: RETRIED_ERRORS

# Load database connection first
require_relative '../../lib/database'

# Run migrations for test database (in-memory SQLite) BEFORE loading app/models
Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

# Now load the app (which loads models) - tables exist now
require_relative '../../app'

Capybara.app = App
Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new app, browser: :chrome
end

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-blink-features=AutomationControlled')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--no-sandbox')
  options.add_argument('--window-size=1400,900')
  Capybara::Selenium::Driver.new app, browser: :chrome, options: options
end

Capybara.register_driver :firefox do |app|
  Capybara::Selenium::Driver.new app, browser: :firefox
end

Capybara.register_driver :headless_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-blink-features=AutomationControlled')
  options.add_preference('dom.webdriver.enabled', false)
  options.add_preference('useAutomationExtension', false)
  # Falcon's Protocol::HTTP::ContentEncoding middleware can produce responses
  # that headless Firefox rejects with contentEncodingError. Requesting only
  # identity encoding avoids the issue.
  options.add_preference('network.http.accept-encoding', 'identity')
  options.add_preference('network.http.accept-encoding.secure', 'identity')
  Capybara::Selenium::Driver.new app, browser: :firefox, options: options
end

# Use headless Firefox everywhere (Chrome crashes on Falcon's logout redirect)
driver = :headless_firefox

Capybara.javascript_driver = driver

Capybara.configure do |config|
  config.server = :falcon
  config.run_server = true
  config.server_port = 9292
  config.default_driver = driver
  config.app_host = 'http://localhost:9292'
end

# Browser specs drive whole flows, so one page load can touch several services.
# See spec/support/default_external_apis.rb for what each answers and why a
# spec overrides rather than adds.
require_relative '../support/default_external_apis'
Minitest::Test.prepend DefaultExternalApis

# Credentials an anonymous visitor carries in the session cache after connecting
# Goodreads. Shared by anonymous_search_spec.rb and anonymous_search_flow_spec.rb,
# which is why it lives here rather than in whichever of them loads first.
ANON_CREDENTIALS = {anon_goodreads_user_id: '1', anon_goodreads_token: 'token', anon_goodreads_secret: 'secret'}.freeze

# Helper module for test utilities
module TestHelpers
  # Two specs in system_spec.rb drive the browser to goodreads.com and through
  # Amazon's sign-in, or need a real library's OverDrive catalogue. That
  # traffic belongs to the browser process, so WebMock can neither block nor
  # stub it -- they are the only specs here that genuinely need the network,
  # real credentials, and a Goodreads account with the right shelves.
  #
  # They are also the specs #1329 is about: roughly a third of main's runs
  # failed on Amazon's CVF challenge or a Selenium timeout, and since
  # autoDeployTrigger is checksPass, that blocked production deploys.
  #
  # Opt in with LIVE_EXTERNAL_SPECS=1 when you have credentials and want to
  # check the real integration. Everything else runs offline.
  def skip_unless_live_external
    return if ENV['LIVE_EXTERNAL_SPECS'] == '1'

    skip 'set LIVE_EXTERNAL_SPECS=1 to run specs that reach Goodreads and OverDrive through the browser'
  end

  # Helper to log in with password via the login page
  def password_login email, password
    visit '/authenticate'
    within('#password-login-form') do
      fill_in 'Email', with: email
      fill_in 'Password', with: password
      click_button 'Log In with Password'
    end
  end

  # Helper method to manually verify an account in tests
  def verify_account email
    # Wait for account to be created (async operation)
    account = nil
    10.times do
      account = DB[:accounts].where(email: email).first
      break if account

      sleep 0.1
    end

    return unless account

    # Update status to verified (status 2)
    DB[:accounts].where(id: account[:id]).update(status_id: 2)
    # Remove verification key if it exists
    DB[:account_verification_keys].where(id: account[:id]).delete
  end

  # Create a verified account directly in the DB (fast, no browser round-trip).
  # Returns [email, password].
  def create_account_direct
    require 'argon2'
    require 'securerandom'
    # Time.now.to_i + rand(9999) collides when two accounts are created in the
    # same second, which surfaced as an intermittent UniqueConstraintViolation
    # on accounts.email.
    email = "test_#{SecureRandom.hex(12)}@example.com"
    password = 'SecurePassword123!'
    hash = Argon2::Password.new(t_cost: 1, m_cost: 5).create(password)
    DB[:accounts].insert(email: email, password_hash: hash, status_id: 2)
    [email, password]
  end

  # Insert a Goodreads connection with required timestamps (raw insert skips model hooks)
  def add_goodreads_connection user_id, goodreads_user_id, token, secret
    now = Time.now
    DB[:goodreads_connections].insert(
      user_id: user_id,
      goodreads_user_id: goodreads_user_id,
      access_token: token,
      access_token_secret: secret,
      connected_at: now,
      created_at: now,
      updated_at: now
    )
  end

  # Create a verified account with Goodreads connected, then log in via browser.
  # Returns the account id.
  def seed_goodreads_user
    email, password = create_account_direct

    # Look up account and add Goodreads connection
    account = DB[:accounts].where(email: email).first
    add_goodreads_connection(account[:id], ENV.fetch('GOODREADS_USER_ID'), ENV.fetch('GOODREADS_ACCESS_TOKEN'), ENV.fetch('GOODREADS_ACCESS_TOKEN_SECRET'))

    # Log in via the browser
    password_login(email, password)
    assert_text 'Welcome back,'

    account[:id]
  end
end

# Include the helper module in Minitest
Minitest::Test.include TestHelpers
