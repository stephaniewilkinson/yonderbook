# frozen_string_literal: true

require_relative 'spec_helper'
require 'secrets'

# The Goodreads key is the one credential here that cannot be replaced: Amazon
# deprecated the API in 2020 and issues no new keys, so a leaked one that gets
# revoked is gone rather than rotated. These specs are what keeps it out of
# anything the app writes down.
describe Secrets do
  def with_env values
    previous = values.to_h { |name, _| [name, ENV.fetch(name, nil)] }
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    Secrets.reset!
    yield
  ensure
    previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    Secrets.reset!
  end

  it 'redacts the key out of a url it was interpolated into' do
    # lib/goodreads.rb builds "/review/list/42.xml?key=#{API_KEY}&...", so this
    # is the exact shape an exception message takes.
    with_env('GOODREADS_API_KEY' => 'abcd1234efgh5678') do
      message = 'Net::OpenTimeout: https://www.goodreads.com/review/list/42.xml?key=abcd1234efgh5678&v=2'

      redacted = Secrets.redact(message)

      refute_includes redacted, 'abcd1234efgh5678'
      assert_includes redacted, Secrets::PLACEHOLDER
      assert_includes redacted, 'goodreads.com', 'redaction should not destroy the rest of the message'
    end
  end

  it 'redacts every occurrence, not just the first' do
    with_env('GOODREADS_API_KEY' => 'abcd1234efgh5678') do
      redacted = Secrets.redact('key=abcd1234efgh5678 retried key=abcd1234efgh5678')

      refute_includes redacted, 'abcd1234efgh5678'
    end
  end

  it 'guards every credential, not only Goodreads' do
    with_env('OVERDRIVE_SECRET' => 'overdrive-secret-value', 'RESEND_API_KEY' => 'resend-key-value') do
      redacted = Secrets.redact('overdrive-secret-value and resend-key-value')

      refute_includes redacted, 'overdrive-secret-value'
      refute_includes redacted, 'resend-key-value'
    end
  end

  it 'replaces a longer secret whole when one contains another' do
    with_env('GOODREADS_SECRET' => 'abcdefgh', 'GOODREADS_API_KEY' => 'abcdefgh12345678') do
      redacted = Secrets.redact('key=abcdefgh12345678')

      refute_includes redacted, 'abcdefgh12345678'
      assert_equal "key=#{Secrets::PLACEHOLDER}", redacted
    end
  end

  # Redacting a short value would corrupt ordinary text for no benefit.
  it 'ignores values too short to be a credential' do
    with_env('GOODREADS_USER_ID' => '1', 'GOODREADS_API_KEY' => 'short') do
      assert_equal 'a book rated 1 of 5', Secrets.redact('a book rated 1 of 5')
    end
  end

  it 'leaves text alone when nothing is configured' do
    with_env(Secrets::GUARDED.to_h { |name| [name, nil] }) do
      assert_equal 'nothing to hide here', Secrets.redact('nothing to hide here')
    end
  end

  it 'passes through anything that is not a string' do
    assert_nil Secrets.redact(nil)
    assert_equal 42, Secrets.redact(42)
  end

  it 'does not guard the user id or the BookMooch username' do
    # Not credentials, and both are short enough or common enough that
    # redacting them would mangle book titles and log lines.
    refute_includes Secrets::GUARDED, 'GOODREADS_USER_ID'
    refute_includes Secrets::GUARDED, 'BOOKMOOCH_USERNAME'
  end
end
