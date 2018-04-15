# frozen_string_literal: true

require 'rinda/tuplespace'

class TupleSpace < Rinda::TupleSpace
  def new reaper_period_in_secs = 600
    super reaper_period_in_secs
  end

  def []= key, value
    take [key, nil], true
  rescue Rinda::RequestExpiredError
    nil
  ensure
    write [key, value], 86_400 # expires_in_secs
  end

  def [] key
    read([key, nil], true).last
  rescue Rinda::RequestExpiredError
    nil
  end
end
