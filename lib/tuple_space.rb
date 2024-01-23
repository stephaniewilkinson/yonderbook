# frozen_string_literal: true

require 'rinda/tuplespace'

class TupleSpace < Rinda::TupleSpace
  # 600 seconds is ten minutes and 86,400 seconds is 24 hours
  def initialize reaper_period_in_secs: 600, expires_in_secs: 86_400
    @expires_in_secs = expires_in_secs
    super(reaper_period_in_secs)
  end

  def []= key, value
    take [key, nil], true
  rescue Rinda::RequestExpiredError
    nil
  ensure
    write [key, value], @expires_in_secs
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
