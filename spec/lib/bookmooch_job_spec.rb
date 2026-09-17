# frozen_string_literal: true

require_relative 'spec_helper'
require 'bookmooch_job'

describe BookmoochJob do
  # The job is the app's only background worker and both of its rescues used to
  # report to the user and to nobody else -- the yield wrote a websocket frame,
  # the Async block ended, and the exception was gone.
  def run_failing_with error
    captured = []
    breadcrumbs = []
    messages = []

    Bookmooch.stub(:books_added_and_failed, ->(*, **, &_) { raise error }) do
      Sentry.stub(:capture_exception, ->(e, **opts) { captured << [e, opts] }) do
        Sentry.stub(:add_breadcrumb, ->(crumb) { breadcrumbs << crumb }) do
          BookmoochJob.run([{isbn: '111'}, {isbn: '222'}], 'steph', 'hunter2', 'session-abc') { |update| messages << update }
        end
      end
    end

    [captured, breadcrumbs, messages]
  end

  it 'reports an unanticipated failure to Sentry as well as to the user' do
    error = RuntimeError.new('connection reset')
    captured, _breadcrumbs, messages = run_failing_with error

    assert_equal 1, captured.size
    assert_same error, captured.first.first
    assert_includes messages, {type: 'error', message: 'An error occurred: connection reset'}
  end

  it 'sends the job size and nothing that grants access to the import' do
    captured, = run_failing_with RuntimeError.new('boom')
    extra = captured.first.last[:extra]

    # Not the credentials, and not session_id either -- that one keys the
    # import's cached data, so it is a capability rather than a correlation id.
    assert_equal({book_count: 2}, extra)
  end

  it 'leaves an expected failure as a breadcrumb rather than an event' do
    captured, breadcrumbs, messages = run_failing_with Bookmooch::AuthenticationError.new('Invalid BookMooch credentials')

    assert_empty captured
    assert_equal %w[bookmooch], breadcrumbs.map(&:category)
    assert_equal ['Bookmooch::AuthenticationError'], breadcrumbs.map(&:message)
    assert_includes messages, {type: 'error', message: 'Invalid BookMooch credentials'}
  end
end
