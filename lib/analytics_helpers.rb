# frozen_string_literal: true

# Mixin for Roda app to provide analytics helpers in routes
module AnalyticsHelpers
  def analytics_id
    @user ? @user.id.to_s : session['session_id']
  end

  def identify_user
    return unless @user

    Analytics.alias_user @user.id.to_s, session['session_id']
    Analytics.identify @user.id.to_s, email: @user.email, goodreads_connected: @user.goodreads_connected?
  end
end
