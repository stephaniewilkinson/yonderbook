# frozen_string_literal: true

require_relative 'spec_helper'
require 'title_normalizer'

describe TitleNormalizer do
  describe '.normalize' do
    it 'removes series info in parentheses' do
      assert_equal 'parable of the sower', TitleNormalizer.normalize('Parable of the Sower (Earthseed, #1)')
    end

    it 'removes subtitles after colons' do
      assert_equal 'the new jim crow', TitleNormalizer.normalize('The New Jim Crow: Mass Incarceration in the Age of Colorblindness')
    end

    it 'downcases and strips punctuation' do
      assert_equal 'its a wonderful life', TitleNormalizer.normalize("It's a Wonderful Life!")
    end

    it 'collapses whitespace' do
      assert_equal 'a tale of two cities', TitleNormalizer.normalize('  A  Tale  of  Two  Cities  ')
    end

    it 'handles both parentheses and colons' do
      assert_equal 'caps for sale', TitleNormalizer.normalize('Caps for Sale: A Tale of a Peddler (Classic Board Books)')
    end
  end

  describe '.clean_for_search' do
    it 'removes series info but preserves case and punctuation' do
      assert_equal 'Parable of the Sower', TitleNormalizer.clean_for_search('Parable of the Sower (Earthseed, #1)')
    end

    it 'removes subtitles after colons' do
      assert_equal 'The New Jim Crow', TitleNormalizer.clean_for_search('The New Jim Crow: Mass Incarceration')
    end

    it 'strips surrounding whitespace' do
      assert_equal 'Caps for Sale', TitleNormalizer.clean_for_search('Caps for Sale: A Tale of a Peddler')
    end
  end
end
