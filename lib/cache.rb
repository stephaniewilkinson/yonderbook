# frozen_string_literal: true

require_relative 'tuple_space'

module Cache
  CACHE = TupleSpace.new

  module_function

  def set session, **pairs
    pairs.each do |key, value|
      CACHE["#{session['session_id']}/#{key}"] = value
    end
  end

  def get session, key
    CACHE["#{session['session_id']}/#{key}"]
  end

  # Set cache values by session ID directly (for background jobs)
  def set_by_id session_id, **pairs
    pairs.each do |key, value|
      CACHE["#{session_id}/#{key}"] = value
    end
  end

  # Get cache value by session ID directly (for background jobs)
  def get_by_id session_id, key
    CACHE["#{session_id}/#{key}"]
  end
end
