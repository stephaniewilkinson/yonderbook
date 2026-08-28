# frozen_string_literal: true

require_relative 'spec_helper'
require 'libby_url'

describe LibbyUrl do
  describe '.for' do
    it 'builds a search URL from a title' do
      assert_equal 'https://www.overdrive.com/search?q=Piranesi', LibbyUrl.for('Piranesi')
    end

    it 'includes the author when there is one, which narrows the results' do
      assert_equal 'https://www.overdrive.com/search?q=Piranesi+Susanna+Clarke', LibbyUrl.for('Piranesi', 'Susanna Clarke')
    end

    it 'encodes characters that would break the query string' do
      assert_includes LibbyUrl.for('Cats & Dogs'), 'q=Cats+%26+Dogs'
    end

    # The Signal bot's schedule stores author as nullable.
    it 'works with no author' do
      refute_nil LibbyUrl.for('Piranesi', nil)
    end

    it 'ignores a blank author rather than trailing a space' do
      assert_equal LibbyUrl.for('Piranesi'), LibbyUrl.for('Piranesi', '   ')
    end

    it 'returns nothing without a title' do
      assert_nil LibbyUrl.for(nil)
    end

    it 'returns nothing for a blank title' do
      assert_nil LibbyUrl.for('   ')
    end
  end
end
