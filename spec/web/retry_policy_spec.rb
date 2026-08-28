# frozen_string_literal: true

require_relative 'spec_helper'

# Guards the retry policy configured in spec_helper.rb.
#
# A retry that is too broad silently converts real, reproducible failures into
# passes on the second attempt. These assertions exist so that widening the list
# has to be a deliberate act rather than a convenient one.
describe 'flaky test retry policy' do
  let(:retried) { Minitest::Retry.exceptions_to_retry }

  it 'retries the driver read timeout that blocks deploys' do
    assert_includes retried, Net::ReadTimeout
  end

  it 'retries driver connection timeouts' do
    assert_includes retried, Selenium::WebDriver::Error::TimeoutError
  end

  it 'never retries assertion failures, which would mask real bugs' do
    refute_includes retried, Minitest::Assertion
  end

  # This is how the import button-label bug surfaced. Retrying it would have
  # hidden a genuine defect.
  it 'never retries element-not-found' do
    refute_includes retried, Capybara::ElementNotFound
  end

  it 'retries a small, fixed number of times' do
    assert_equal 2, Minitest::Retry.retry_count
  end

  it 'restricts retries to an explicit list rather than everything' do
    refute_empty retried
  end
end
