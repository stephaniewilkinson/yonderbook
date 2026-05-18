# frozen_string_literal: true

# OAuth callback helpers for both authenticated and anonymous Goodreads flows
module OauthHelpers
  def require_cached_request_token request
    token = Cache.get session, :request_token
    return token if token

    flash[:error] = "Please click 'Connect with Goodreads' again"
    request.redirect '/'
  end

  def handle_anonymous_oauth_callback request, request_token
    credentials = Goodreads.exchange_token(request_token)
    store_goodreads_in_session(credentials)
    Analytics.track analytics_id, 'goodreads_connected_anonymous', goodreads_user_id: credentials[:user_id]
    request.redirect '/search/shelves'
  rescue OAuth::Unauthorized
    flash[:error] = "Almost there — click 'Connect with Goodreads' one more time"
    request.redirect '/'
  end

  def handle_authenticated_oauth_callback request, request_token
    unless @user
      flash[:error] = 'Please log in first before connecting Goodreads'
      request.redirect '/'
    end
    Goodreads.fetch_user request_token, @user.id
    @user.refresh
    gr_user_id = @user.goodreads_connection&.goodreads_user_id
    Analytics.identify analytics_id, goodreads_user_id: gr_user_id
    Analytics.track analytics_id, 'goodreads_connected', goodreads_user_id: gr_user_id
    request.redirect '/goodreads/shelves'
  rescue OAuth::Unauthorized
    flash[:error] = 'Fetched details! Click login'
    request.redirect '/'
  end
end
