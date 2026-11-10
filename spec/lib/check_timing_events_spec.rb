# frozen_string_literal: true

require_relative 'spec_helper'
require 'availability_helpers'

# #1403: before deciding whether searching several libraries is too slow,
# measure it. The progress page reports how long a check took, bucketed, for
# each number of libraries a reader can pick.
describe 'check timing events' do
  BUCKETS = %w[under_30s 30_to_90s over_90s].freeze

  def progress_page = File.read(File.expand_path('../../views/availability_progress.erb', __dir__))

  it 'has a set of events for every number of libraries a reader can pick' do
    (1..AvailabilityHelpers::MAX_LIBRARIES).each do |count|
      libraries = count == 1 ? '1_library' : "#{count}_libraries"
      BUCKETS.each do |bucket|
        assert_includes progress_page, "'check_#{libraries}_#{bucket}'"
      end
    end
  end

  it 'times from the library form, where the count is recorded' do
    library_page = File.read(File.expand_path('../../views/library.erb', __dir__))

    assert_includes library_page, "sessionStorage.setItem('yonderbook.check'"
    assert_includes progress_page, 'reportCheckTime();'
  end
end
