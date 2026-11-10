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

  # #1422. Replaced the Kit form, which posted to nothing.
  describe 'the alerts prompt' do
    it 'offers alerts through a free account' do
      html = render_conversion

      assert_includes html, 'Create a free account for alerts'
      assert_includes html, 'href="/sign-up"'
    end

    it 'has no email form left over from Kit' do
      refute_includes render_conversion, 'kit-notify-form'
    end
  end
end
