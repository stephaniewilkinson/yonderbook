# frozen_string_literal: true

require_relative 'spec_helper'
require 'overdrive'

describe Overdrive do
  describe '.Title' do
    it 'creates a title with all fields' do
      title = Overdrive::Title.new(
        title: 'Test Book',
        author: 'Author',
        image: 'http://img.jpg',
        copies_available: 2,
        copies_owned: 5,
        isbn: '123',
        url: 'http://link',
        id: 'abc',
        availability_url: nil,
        no_isbn: false,
        date_added: '2024-01-01'
      )
      assert_equal 'Test Book', title.title
      assert_equal 2, title.copies_available
      assert_equal 5, title.copies_owned
      refute title.no_isbn
    end

    it 'supports with() to create modified copies' do
      title = Overdrive::Title.new(
        title: 'Book',
        author: 'A',
        image: nil,
        copies_available: 0,
        copies_owned: 0,
        isbn: '123',
        url: nil,
        id: nil,
        availability_url: nil,
        no_isbn: false,
        date_added: nil
      )
      updated = title.with(copies_available: 3, copies_owned: 10)
      assert_equal 3, updated.copies_available
      assert_equal 10, updated.copies_owned
      assert_equal 'Book', updated.title
    end
  end

  describe '#should_replace? (via consolidation logic)' do
    def make_title available:, owned:
      Overdrive::Title.new(
        title: 'T',
        author: 'A',
        image: nil,
        copies_available: available,
        copies_owned: owned,
        isbn: '123',
        url: nil,
        id: nil,
        availability_url: nil,
        no_isbn: false,
        date_added: nil
      )
    end

    it 'prefers edition with availability over one without' do
      available = make_title(available: 1, owned: 5)
      unavailable = make_title(available: 0, owned: 5)

      od = Overdrive.allocate
      assert od.send(:should_replace?, available, unavailable)
      refute od.send(:should_replace?, unavailable, available)
    end

    it 'prefers edition with more copies when both available' do
      more = make_title(available: 3, owned: 5)
      less = make_title(available: 1, owned: 5)

      od = Overdrive.allocate
      assert od.send(:should_replace?, more, less)
      refute od.send(:should_replace?, less, more)
    end
  end

  describe '#title_matches_exactly?' do
    def check_match overdrive_title, goodreads_title
      product = {'title' => overdrive_title}
      od = Overdrive.allocate
      od.send(:title_matches_exactly?, product, goodreads_title)
    end

    it 'matches identical titles after normalization' do
      assert check_match('The Outsiders', 'The Outsiders')
    end

    it 'matches when Goodreads title starts with OverDrive title' do
      assert check_match('Beloved', 'Beloved (Pulitzer Prize Winner)')
    end

    it 'matches when OverDrive title starts with Goodreads title' do
      assert check_match('The Great Gatsby: The Authorized Edition', 'The Great Gatsby')
    end

    it 'does not match unrelated titles' do
      refute check_match('Dune', 'Foundation')
    end
  end

  describe '#author_matches?' do
    def check_author product_author, target_author
      product = {'primaryCreator' => {'name' => product_author}}
      od = Overdrive.allocate
      od.send(:author_matches?, product, target_author)
    end

    it 'matches by last name' do
      assert check_author('S.E. Hinton', 'Susan Eloise Hinton')
    end

    it 'does not match different authors' do
      refute check_author('Stephen King', 'J.K. Rowling')
    end

    it 'returns false for nil target author' do
      refute check_author('Someone', nil)
    end

    it 'returns false for empty target author' do
      refute check_author('Someone', '')
    end
  end
end
