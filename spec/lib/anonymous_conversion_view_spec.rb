# frozen_string_literal: true

require_relative 'spec_helper'
require 'tilt'

# The conversion cards shown to someone who reached results without an account.
# Rendered through Tilt rather than a request: this is the partial's own markup,
# and the route that reaches it is covered in spec/web/anonymous_search_spec.rb.
describe 'views/_anonymous_conversion.erb' do
  def render_conversion = Tilt.new('views/_anonymous_conversion.erb').render(Object.new)

  describe 'always' do
    it 'offers an account without blocking anything on it' do
      html = render_conversion

      assert_includes html, 'Create a free account'
      assert_includes html, 'href="/sign-up"'
    end

    it 'says what the account is actually for' do
      # #1355: nothing told a visitor why they would want one, which makes
      # signup a pure cost.
      html = render_conversion

      assert_includes html, 'reconnect'
      assert_includes html, 'BookMooch'
    end

    it 'lets the prompt be dismissed' do
      html = render_conversion

      assert_includes html, 'Maybe later'
      assert_includes html, "document.getElementById('save-results-card').remove()"
    end

    it 'teases analytics against the shelf just searched' do
      html = render_conversion

      assert_includes html, 'See your reading patterns'
      assert_includes html, 'Unlock reading analytics'
    end

    it 'keeps every link in the same tab' do
      # target="_blank" opens a tab Capybara does not follow.
      refute_includes render_conversion, '_blank'
    end
  end

  describe 'the Kit email form' do
    # The form posts straight to Kit, so a deploy without the URL configured
    # should have no form at all rather than one that silently fails.
    it 'is absent when KIT_FORM_ACTION_URL is unset' do
      html = with_kit_url(nil) { render_conversion }

      refute_includes html, 'kit-notify-form'
      refute_includes html, 'Notify me'
    end

    it 'is absent when KIT_FORM_ACTION_URL is set but empty' do
      html = with_kit_url('') { render_conversion }

      refute_includes html, 'kit-notify-form'
    end

    it 'posts to the configured Kit endpoint when one is set' do
      html = with_kit_url('https://app.kit.com/forms/123/subscriptions') { render_conversion }

      assert_includes html, 'action="https://app.kit.com/forms/123/subscriptions"'
      assert_includes html, 'name="email_address"'
    end

    it 'submits without leaving the results page' do
      html = with_kit_url('https://app.kit.com/forms/123/subscriptions') { render_conversion }

      assert_includes html, 'event.preventDefault()'
      assert_includes html, 'fetch(form.action'
    end

    it 'reports both outcomes inline' do
      html = with_kit_url('https://app.kit.com/forms/123/subscriptions') { render_conversion }

      assert_includes html, 'Subscribed.'
      assert_includes html, 'That did not go through'
    end

    it 'labels the email field for screen readers' do
      html = with_kit_url('https://app.kit.com/forms/123/subscriptions') { render_conversion }

      assert_includes html, 'for="kit-email"'
      assert_includes html, 'aria-live="polite"'
    end
  end

  def with_kit_url value
    previous = ENV.fetch('KIT_FORM_ACTION_URL', nil)
    value.nil? ? ENV.delete('KIT_FORM_ACTION_URL') : ENV['KIT_FORM_ACTION_URL'] = value
    yield
  ensure
    previous.nil? ? ENV.delete('KIT_FORM_ACTION_URL') : ENV['KIT_FORM_ACTION_URL'] = previous
  end
end
