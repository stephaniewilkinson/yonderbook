# frozen_string_literal: true

require 'posthog'

module Analytics
  POSTHOG = PostHog::Client.new(
    api_key: 'phc_Vh8tLIw5ZSJZgeqGOpQsAkhIkegbcLp47D3PAmBVvH4',
    host: 'https://us.i.posthog.com',
    on_error: proc { |status, msg| warn "PostHog error: #{status} #{msg}" }
  )

  at_exit { POSTHOG.shutdown }

  module_function

  def track session_id, event, properties = {}
    POSTHOG.capture(distinct_id: session_id, event: event, properties: properties)
  rescue StandardError => e
    warn "PostHog tracking error: #{e.message}"
  end

  def identify session_id, properties = {}
    POSTHOG.capture(distinct_id: session_id, event: '$identify', properties: {'$set': properties})
  rescue StandardError => e
    warn "PostHog tracking error: #{e.message}"
  end
end
