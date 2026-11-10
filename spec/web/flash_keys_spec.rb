# frozen_string_literal: true

require_relative 'spec_helper'

# #1428. Roda keeps a flash key's type across a redirect: a message set as
# flash[:error] is still under :error on the next request, where the views
# read flash['error']. The app mixed both, and messages set with symbols were
# silently dropped. String keys only, the same as Rodauth uses.
describe 'flash keys' do
  ROOT = File.expand_path('../..', __dir__)
  SOURCES = Dir["#{ROOT}/{app.rb,lib/**/*.rb,views/**/*.erb}"].freeze

  it 'are strings everywhere the app sets or reads one' do
    symbol_keys = SOURCES.flat_map do |path|
      File.foreach(path).with_index(1).filter_map do |line, number|
        next if line.strip.start_with?('#', '<%#') || !line.match?(/flash(?:\.now)?\[:\w+\]/)

        "#{path.delete_prefix("#{ROOT}/")}:#{number}"
      end
    end

    assert_empty symbol_keys, "Use string flash keys (flash['error']):\n#{symbol_keys.join("\n")}"
  end
end
