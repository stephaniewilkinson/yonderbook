# frozen_string_literal: true

# Checking more than one library for the same shelf.
#
# Lives apart from the single-library client because it is a different job:
# Overdrive talks to one consortium, and this decides how many of them to ask
# and in what order.
class Overdrive
  # What a multi-library check produced: every copy found, and each library's
  # OverDrive deep link, which is where "search your library" points for a book
  # nobody owns.
  Availability = Data.define(:copies, :library_urls)

  # Check several libraries, cheapest-first rather than all at once.
  #
  # The product search is scoped to a collection token, so every book has to be
  # searched again per consortium -- this is N times the whole pipeline, not
  # just the availability calls, and the search phase is already the
  # bottleneck. Fanning out across libraries in parallel multiplies the most
  # expensive thing the app does.
  #
  # So: a book stops being searched once it is available somewhere. An
  # available copy ends the reader's question, and the books that do continue
  # -- waitlisted and not-owned -- are exactly the ones where another library
  # changes the answer. On a shelf where the first library has most of what
  # someone wants, the second costs a fraction of a full pass.
  #
  # Libraries are tried in the order given, which is the reader's own.
  def self.fetch_across_libraries(book_info, libraries, &)
    remaining = book_info
    copies = []
    library_urls = {}

    libraries.each do |consortium_id, library_name|
      break if remaining.empty?

      overdrive = new(remaining, consortium_id)
      found = overdrive.fetch_titles_availability(&)
      copies.concat(found.map { |copy| copy.with(library: library_name) })
      library_urls[library_name] = overdrive.library_url

      settled = found.filter_map { |copy| book_key(copy.isbn, copy.title) if copy.copies_available.to_i.positive? }.to_set
      remaining = remaining.reject { |book| settled.include? book_key(book[:isbn], book[:title]) }
    end

    Availability.new(copies: copies, library_urls: library_urls)
  end
end
