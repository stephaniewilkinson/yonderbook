# frozen_string_literal: true

require 'rinda/tuplespace'

class TupleSpace < Rinda::TupleSpace
  # Reaper runs every 10 minutes, tuples expire after 30 minutes
  def initialize reaper_period_in_secs: 600, expires_in_secs: 1_800
    @expires_in_secs = expires_in_secs
    super(reaper_period_in_secs)
  end

  attr_reader :expires_in_secs

  def []= key, value
    store key, value
  end

  # `[]=` cannot take a third argument, so anything wanting a lifetime other
  # than the default calls this. Cache uses it to expire an abandoned anonymous
  # session sooner than a signed-in one.
  #
  # Note the TTL is refreshed on every write, so an actively used session
  # extends indefinitely. That is intended: this only bounds abandoned
  # sessions, which is exactly the case worth bounding.
  def store key, value, expires_in_secs: @expires_in_secs
    take [key, nil], true
  rescue Rinda::RequestExpiredError
    nil
  ensure
    write [key, value], expires_in_secs
  end

  def [] key
    read([key, nil], true).last
  rescue Rinda::RequestExpiredError
    nil
  end

  def delete key
    take([key, nil], true).last
  rescue Rinda::RequestExpiredError
    nil
  end
end
