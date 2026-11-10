# frozen_string_literal: true

require_relative 'spec_helper'
require 'goodreads_csv'

# A StoryGraph export goes through the same import as a Goodreads one: the
# headers say which it is, and its rows come out in the same book shape.
describe StorygraphCsv do
  def books
    @books ||= GoodreadsCsv.parse File.read(File.expand_path('../fixtures/storygraph_export.csv', __dir__))
  end

  def book(titled) = books.find { |each| each[:title] == titled }

  it 'is recognised from its headers and read in full' do
    assert_equal(['Piranesi', 'The Left Hand of Darkness', 'A Book With No ISBN'], books.map { |each| each[:title] })
  end

  it 'turns the read status into the main shelf, and tags into more shelves' do
    assert_equal 'to-read', book('Piranesi')[:exclusive_shelf]
    assert_equal ['to-read', 'fantasy', 'book club'], book('Piranesi')[:shelves]
    assert_equal ['currently-reading'], book('A Book With No ISBN')[:shelves]
  end

  it "keeps a real ISBN and drops StoryGraph's own id" do
    assert_equal '9781635575996', book('Piranesi')[:isbn]
    assert_nil book('A Book With No ISBN')[:isbn]
  end

  it 'takes the first of several authors' do
    assert_equal 'Ursula K. Le Guin', book('The Left Hand of Darkness')[:author]
  end

  it 'rounds quarter-star ratings to whole stars' do
    assert_equal 4, book('The Left Hand of Darkness')[:ratings]
    assert_equal 0, book('Piranesi')[:ratings]
  end

  it 'reads the date formats importers report, as ISO dates' do
    assert_equal '2024-03-02', book('Piranesi')[:date_added]
    assert_equal '2023-11-15', book('The Left Hand of Darkness')[:date_added]
    assert_equal '2024-03-05', book('A Book With No ISBN')[:date_added]
  end

  it 'lists its shelves for the shelf picker' do
    counts = GoodreadsCsv.shelf_counts(books).to_h

    assert_equal 1, counts['to-read']
    assert_equal 1, counts['read']
  end

  it 'still turns away a file that is neither export, naming both' do
    error = assert_raises(GoodreadsCsv::InvalidFormat) { GoodreadsCsv.parse "Title,Pages\nA,1\n" }

    assert_includes error.message, 'StoryGraph'
  end
end
