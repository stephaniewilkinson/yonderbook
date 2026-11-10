# frozen_string_literal: true

require_relative 'spec_helper'
require 'tempfile'

# #1415. Titles and authors come from Goodreads or an uploaded CSV and used to
# be printed as raw HTML, so a crafted export could put markup on the page.
describe 'text from an uploaded library' do
  include Capybara::DSL
  include Minitest::Capybara::Behaviour

  PAYLOAD = '<script>window.pwned=1</script><img src=x onerror=alert(1)>'

  def import_library_titled title
    csv = Tempfile.new(['export', '.csv'])
    csv.write <<~CSV
      Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Owned Copies
      1,"#{title}",Ann Author,"Author, Ann",,,,4,4.0,Pub,Paperback,100,2001,2001,,2024/01/01,to-read,to-read (#1),to-read,,,,0,0
    CSV
    csv.close

    email, password = create_account_direct
    password_login email, password
    visit '/import'
    attach_file 'library', csv.path
    click_button 'import-submit'
    assert_current_path '/goodreads/shelves'
  ensure
    csv&.unlink
  end

  it 'is escaped on the stats page, including inside the chart data' do
    import_library_titled PAYLOAD
    visit '/goodreads/shelves/to-read'

    html = page.html
    refute_includes html, PAYLOAD, 'the title reached the page as markup'
    # The chart data sits in a <script> block: "</script>" in a title must not end it.
    chart_data = html[/const booksData = (.*?);\n/, 1]
    refute_nil chart_data
    refute_includes chart_data, '</script>'
    # Still the same title once JavaScript parses it: \u003c decodes to "<".
    assert_includes chart_data, '\u003cscript\u003e'
  end

  it 'is escaped in the page markup everywhere it is shown' do
    import_library_titled 'Title <b>bold</b> & more'
    visit '/goodreads/shelves/to-read'

    refute_includes page.html, '<b>bold</b>'
  end
end
