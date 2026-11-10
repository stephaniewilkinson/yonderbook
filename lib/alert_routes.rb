# frozen_string_literal: true

require_relative 'availability_alerts'

# Routes for availability alerts (#1422). See AvailabilityAlerts for the check.
module AlertRoutes
  # Two Falcon threads share this process. A second check starting while one
  # runs would read the same "due" subscriptions and email them twice. A flag,
  # not a held Mutex: a Mutex belongs to the fiber that locked it, and the
  # check finishes in a different one.
  CHECK_GUARD = Mutex.new
  @check_running = false

  def self.claim_check = CHECK_GUARD.synchronize { @check_running ? false : (@check_running = true) }

  def self.release_check = CHECK_GUARD.synchronize { @check_running = false }

  def handle_alert_routes request
    # route: POST /alerts/check
    # The Render cron job's daily call (render.yaml), with a bearer token.
    request.post('check') { start_alert_check request }

    # route: GET /alerts/unsubscribe/:token
    # route: POST /alerts/unsubscribe/:token
    # The link in every alert email: the token is the credential, so no login.
    # GET only shows a button, because mail scanners open links and would turn
    # alerts off by themselves. POST is also what a mail app's one-click
    # unsubscribe (List-Unsubscribe-Post, RFC 8058) sends.
    request.is 'unsubscribe', String do |token|
      @unsubscribe_token = token
      request.get { view 'alerts_unsubscribe' }
      request.post do
        @unsubscribed = AvailabilityAlerts.unsubscribe_by_token token
        view 'alerts_unsubscribe'
      end
    end

    rodauth.require_login

    # route: POST /alerts
    # Turns alerts on from the results the reader is looking at.
    request.post(true) { turn_alerts_on request }

    # route: POST /alerts/off
    request.post 'off' do
      check_csrf!
      AvailabilityAlerts.unsubscribe @user.id
      flash[:notice] = 'Alerts are off, and the list they were watching has been deleted.'
      request.redirect(request.params['from'] == 'results' ? '/goodreads/availability' : '/account')
    end
  end

  def turn_alerts_on request
    check_csrf!
    titles = Cache.get session, :titles
    libraries = Cache.get session, :availability_libraries
    unless titles && libraries
      flash[:error] = 'Those results have expired. Check your libraries again, then turn on alerts.'
      request.redirect '/goodreads/shelves'
    end

    AvailabilityAlerts.subscribe @user.id,
                                 titles: titles,
                                 libraries: libraries,
                                 books: Cache.get(session, :availability_book_info),
                                 shelf_name: Cache.get(session, :shelf_name)
    flash['fathom_event'] = 'notify_subscribed'
    flash[:notice] = "Alerts are on. We'll email you when a book on your list has a copy free."
    request.redirect '/goodreads/availability'
  end

  # A 404, not a 401, without the right token: nothing says the route exists.
  def start_alert_check request
    expected = ENV.fetch('ALERTS_TOKEN', '')
    given = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
    unless !expected.empty? && Rack::Utils.secure_compare(expected, given)
      response.status = 404
      request.halt
    end

    response.status = 202
    return 'already running' unless AlertRoutes.claim_check

    run_alert_check_in_background
    'started'
  end

  # The check outlives the cron's request, which returns at once. Without a
  # fiber scheduler (specs under Rack::Test) it runs inline instead.
  def run_alert_check_in_background
    unless Fiber.scheduler
      begin
        return AvailabilityAlerts.run_due
      ensure
        AlertRoutes.release_check
      end
    end

    Async::Task.current.async(transient: true) do
      AvailabilityAlerts.run_due
    rescue StandardError => e
      Sentry.capture_exception e
    ensure
      AlertRoutes.release_check
    end
  end
end
