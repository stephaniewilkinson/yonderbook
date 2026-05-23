# frozen_string_literal: true

# Mixin for Roda app to provide analytics helpers in routes
module AnalyticsHelpers
  def analytics_id
    @user ? @user.id.to_s : session['session_id']
  end

  def identify_user
    return unless @user
    return if session['posthog_identified']

    Analytics.alias_user @user.id.to_s, session['session_id']

    name = [@user.first_name, @user.last_name].compact.reject(&:empty?).join(' ')
    properties = {
      '$email': @user.email,
      '$name': name.empty? ? @user.email : name,
      first_name: @user.first_name,
      last_name: @user.last_name,
      goodreads_connected: @user.goodreads_connected?,
      created_at: @user.created_at&.iso8601
    }

    Analytics.identify @user.id.to_s, properties
    session['posthog_identified'] = true
  end
end
