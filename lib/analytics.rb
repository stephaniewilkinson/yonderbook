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

  def track distinct_id, event, properties = {}
    POSTHOG.capture(distinct_id: distinct_id, event: event, properties: properties)
  rescue StandardError => e
    warn "PostHog tracking error: #{e.message}"
  end

  def identify distinct_id, properties = {}
    POSTHOG.identify(distinct_id: distinct_id, properties: {'$set': properties})
  rescue StandardError => e
    warn "PostHog identify error: #{e.message}"
  end

  def alias_user distinct_id, alias_id
    POSTHOG.alias(distinct_id: distinct_id, alias: alias_id)
  rescue StandardError => e
    warn "PostHog alias error: #{e.message}"
  end
end
