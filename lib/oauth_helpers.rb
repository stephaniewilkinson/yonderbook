# frozen_string_literal: true

# OAuth callback helpers for both authenticated and anonymous Goodreads flows
module OauthHelpers
  def require_cached_request_token request
    token = Cache.get session, :request_token
    return token if token

    flash[:error] = "Please click 'Connect with Goodreads' again"
    request.redirect '/'
  end

  # The homepage's Goodreads button. Kept off `/` because caching a request
  # token keys on the session id, which the root route deliberately does not
  # assign -- see the comment there.
  #
  # fetch_and_cache_request_token swallows failures and returns nil, so the
  # fallback keeps a dead Goodreads from redirecting the visitor to nowhere.
  def redirect_to_goodreads_authorization request
    request_token = fetch_and_cache_request_token
    request.redirect request_token&.authorize_url || '/'
  end

  # Anonymous visitors go straight to their shelves; signed-in ones to their
  # home page. Everyone else gets the search interface. All reads -- nothing
  # here may write to the session.
  def root_response request
    request.redirect '/home' if @user
    request.redirect '/search/shelves' if goodreads_session_present?
    view 'search'
  end

  def handle_anonymous_oauth_callback request, request_token
    credentials = Goodreads.exchange_token(request_token)
    store_goodreads_in_session(credentials)
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
    request.redirect '/goodreads/shelves'
  rescue OAuth::Unauthorized
    flash[:error] = 'Fetched details! Click login'
    request.redirect '/'
  end
end
