# frozen_string_literal: true

require 'time'

# Ordering books by when they were added to a shelf.
#
# This cannot be a string comparison. Goodreads returns date_added as RFC 2822
# with the weekday first and the year LAST -- "Mon Jan 01 00:00:00 -0800 2024"
# -- so comparing raw strings sorts by weekday abbreviation and the year barely
# participates, putting 2015 books above 2024 ones. The CSV importer stores ISO
# dates, so both formats have to compare correctly against each other too.
module DateAdded
  EPOCH = Time.at(0).freeze

  module_function

  # Missing or unparseable values become the epoch so they sort last rather
  # than raising -- date_added is already nil for some OverDrive results.
  def to_time value
    Time.parse value.to_s
  rescue ArgumentError, RangeError
    EPOCH
  end

  # Newest addition first.
  def sort_desc books
    books.sort_by { |book| to_time book.date_added }.reverse
  end
end
