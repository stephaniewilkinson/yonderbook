# frozen_string_literal: true

require_relative 'spec_helper'

# `hidden` is a display utility like any other, so pairing it with `block` or
# `inline-flex` in one class attribute is a coin flip decided by the order
# Tailwind emits the rules in -- both selectors carry the same specificity and
# the later one wins. In the current build `.hidden` lands at byte 11299 and
# `.inline-flex` at 11355, so `hidden inline-flex` renders *visible*: it left a
# "Try Again" button on screen through every healthy BookMooch import (#1342)
# and put a disabled "Sending to BookMooch..." button next to the Authenticate
# one on the credentials form.
#
# Nothing warns about this -- the markup looks right, and the pair that happens
# to work today (`hidden block`) can flip on a Tailwind upgrade. So assert the
# combination is absent and let the JS add the display utility when it drops
# `hidden`.
DISPLAY_UTILITIES = %w[block inline-block inline flex inline-flex grid inline-grid table inline-table flow-root contents list-item table-row table-cell].freeze

describe 'view display classes' do
  it 'never pairs hidden with another display utility' do
    offenders = Dir.glob('views/**/*.erb').flat_map do |file|
      File.read(file).scan(/class="([^"]*)"/).filter_map do |(attribute)|
        classes = attribute.split
        next unless classes.include?('hidden')

        clashing = classes & DISPLAY_UTILITIES
        "#{file}: `hidden` alongside `#{clashing.join('`, `')}`" unless clashing.empty?
      end
    end

    assert_empty offenders, <<~MESSAGE
      These elements will not hide. Drop the display utility from the class
      attribute and have the script add it when it removes `hidden`:

      #{offenders.join("\n")}
    MESSAGE
  end
end
