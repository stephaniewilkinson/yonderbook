# frozen_string_literal: true

require 'json'

# Copy that appears in more than one place, kept in one place.
#
# Several pages had drifted apart while saying the same thing: the FAQ answers
# existed twice per answer (once in JSON-LD, once in visible HTML), the
# Goodreads two-click explanation was worded four different ways, and the stats
# bar was duplicated across two templates. Each of those is a silent
# half-edit waiting to happen, and Google treats structured data that does not
# match the visible page as a markup violation.
module SiteCopy
  LAUNCH_YEAR = 2016

  # The homepage said "10 Years running" next to "Since 2016". Correct in 2026,
  # wrong in 2027, and nothing would have flagged it. The footer already derives
  # its year this way.
  def self.years_running = Time.now.year - LAUNCH_YEAR

  # The Goodreads connection takes two clicks, and this is the only explanation
  # of it. It has to say what each click does -- "you may need to press it
  # again" tells someone the symptom and not the cause -- and it has to offer
  # the CSV import, which is the one piece of information that removes the
  # problem rather than excusing it.
  TWO_CLICK_HEADING = 'Why two clicks?'
  TWO_CLICK_BODY = 'The first click sends you to Goodreads to authorize Yonderbook. The second, once you are back here, completes the connection. ' \
                   'Goodreads deprecated their API in 2020, which broke the automatic redirect between those two steps.'
  # Split so the CSV offer can carry a link without the sentence being rebuilt
  # at each call site.
  TWO_CLICK_ALTERNATIVE_LEAD = 'Would rather not?'
  TWO_CLICK_ALTERNATIVE_LINK = 'Upload a Goodreads CSV export'
  TWO_CLICK_ALTERNATIVE_TAIL = 'instead and skip connecting altogether.'

  # Figures on the homepage stats bar. `source` is not rendered -- it records
  # where each number came from so the next person can re-check it rather than
  # guess. A number a reader can tell is invented costs more than no number.
  STATS = [
    {figure: '4,800+', label: 'Readers served', source: 'Google Analytics'},
    {figure: -> { years_running.to_s }, label: 'Years running', source: "derived from LAUNCH_YEAR (#{LAUNCH_YEAR})"},
    {figure: '1,000+', label: 'Libraries searchable', source: "OverDrive's consortium list"},
    {figure: '$0', label: 'Cost to readers', source: 'see FAQ, "Is Yonderbook free to use?"'}
  ].freeze

  def self.stats
    STATS.map { |stat| stat.merge(figure: stat[:figure].respond_to?(:call) ? instance_exec(&stat[:figure]) : stat[:figure]) }
  end

  # The steps a visitor actually walks through. The HowTo schema on
  # /how-it-works used to list "select your library" before "choose a shelf"
  # and point two steps at the same URL -- markup Google can lift into a rich
  # result, so it was instructions to real people that did not match the app.
  #
  # The real order is the anonymous flow: pick a shelf, give a zip code, pick a
  # library from the ones nearby, read the results.
  STEPS = [
    {
      name: 'Connect your Goodreads shelves',
      url: 'https://yonderbook.com/connect',
      text: 'Authorize Yonderbook to read your Goodreads shelves, or upload a CSV export instead. No account required.'
    },
    {
      name: 'Choose a shelf to search',
      url: 'https://yonderbook.com/search/shelves',
      text: 'Pick which shelf you want to check -- your want-to-read list, or any other shelf.'
    },
    # No url: the zip form lives under the chosen shelf
    # (/search/shelves/:name/overdrive), so there is no stable address for it.
    # Schema.org allows a step without one, and pointing this at the shelf
    # index -- which is what it used to do -- sent people to the wrong page.
    {
      name: 'Enter your zip code',
      text: 'Tell us roughly where you are so we can find the libraries near you.'
    },
    {
      name: 'Choose your library',
      url: 'https://yonderbook.com/search/library',
      text: 'Pick your library from the ones serving your area.'
    },
    {
      name: 'See what you can borrow',
      url: 'https://yonderbook.com/search/availability',
      text: 'Yonderbook checks every book on the shelf against that library and shows you what is available now.'
    }
  ].freeze

  # One answer per question, rendered into both the FAQPage JSON-LD and the
  # visible page, so the two cannot drift.
  FAQ = [
    {
      question: 'How do I connect my Goodreads account to Yonderbook?',
      answer: 'Click "Connect with Goodreads" on the homepage -- you do not need an account first. ' \
              'You will be sent to Goodreads to authorize the connection, and a second click back here completes it. ' \
              'Goodreads deprecated their API in 2020, which broke the automatic redirect between those two steps. ' \
              'If you would rather not connect at all, you can upload a Goodreads CSV export instead.'
    },
    {
      question: 'Do I need a Yonderbook account?',
      answer: 'No. You can connect Goodreads, search your shelves and see what your library has without one. ' \
              'An account saves your connection so you do not have to reconnect each visit, keeps your imported shelves between sessions, ' \
              'and is required for BookMooch imports, which act on your behalf on another site.'
    },
    {
      question: 'Is Yonderbook free to use?',
      answer: 'Yes. Yonderbook is free to use. It helps you find books you can borrow from your library or trade on BookMooch, which are free too.'
    },
    {
      question: 'What is Libby and how does it work with Yonderbook?',
      answer: 'Libby is a free app by OverDrive that lets you borrow ebooks and audiobooks from your local library. ' \
              "Yonderbook checks if books on your Goodreads want-to-read list are available through your library's Libby catalog, " \
              'so you can borrow them for free instead of buying them.'
    },
    {
      question: 'What is BookMooch?',
      answer: 'BookMooch is a book trading community where readers swap physical books for free (you just pay postage). ' \
              'When you add books to your BookMooch wishlist, you get notified when someone lists a copy. ' \
              'Yonderbook helps you add books from your Goodreads list to your BookMooch wishlist automatically.'
    },
    {
      question: 'Does Yonderbook store my Goodreads data?',
      answer: 'Only the minimum needed to provide the service: your Goodreads user ID and secure connection credentials, and only if you create an account. ' \
              'Your book lists are fetched fresh from Goodreads each time you use Yonderbook. ' \
              'You can disconnect Goodreads and delete everything stored at any time from your Account page.'
    },
    {
      question: 'Which libraries does Yonderbook support?',
      answer: 'Yonderbook works with any library that uses OverDrive/Libby for their digital catalog. ' \
              'That includes most public libraries in the United States, Canada, the UK, Australia and many other countries. ' \
              'Enter your zip code and Yonderbook finds the libraries near you.'
    },
    {
      question: 'Can I use Yonderbook without Goodreads?',
      answer: 'You can upload a Goodreads CSV export rather than connecting your account, but the book list still has to come from Goodreads. ' \
              'Support for other book tracking platforms is not available yet.'
    }
  ].freeze

  # Structured data, built from the same constants the visible pages render, so
  # the two cannot drift. Both used to be typed out separately from the page
  # they describe.
  def self.faq_json_ld
    JSON.pretty_generate(
      {
        '@context' => 'https://schema.org',
        '@type' => 'FAQPage',
        'mainEntity' => FAQ.map do |entry|
          {
            '@type' => 'Question',
            'name' => entry[:question],
            'acceptedAnswer' => {'@type' => 'Answer', 'text' => entry[:answer]}
          }
        end
      },
      script_safe: true
    )
  end

  def self.how_to_json_ld
    JSON.pretty_generate(
      {
        '@context' => 'https://schema.org',
        '@type' => 'HowTo',
        'name' => 'How to Find Free Library Books from Your Goodreads List',
        'description' => 'Use Yonderbook to find books from your Goodreads want-to-read list at your local library ' \
                         'via Libby/OverDrive and through BookMooch book trading.',
        'step' => STEPS.each_with_index.map do |step, index|
          {
            '@type' => 'HowToStep',
            'position' => index + 1,
            'name' => step[:name],
            'text' => step[:text]
          }.tap { |node| node['url'] = step[:url] if step[:url] }
        end
      },
      script_safe: true
    )
  end
end
