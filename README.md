[ ![Codeship Status for stephaniewilkinson/bookmooch](https://app.codeship.com/projects/859f6a90-2275-0136-c761-0e1a22c436f6/status?branch=master)](https://app.codeship.com/projects/286021)

# Tools for Bookworms 📒

## Installation

```
git clone git@github.com:stephaniewilkinson/bookmooch.git
cd bookmooch
cp .env-example .env # if you msg me I can share my api keys
createuser -U postgres bookmooch
createdb -U postgres -O bookmooch bookmooch_production
createdb -U postgres -O bookmooch bookmooch_test
createdb -U postgres -O bookmooch bookmooch_development
rake migrate
rackup
```

## Testing

$ ruby spec/spec.rb

TODO: Clearly display the Goodreads name or logo on any location where Goodreads data appears. For instance if you are displaying Goodreads reviews, they should either be in a section clearly titled "Goodreads Reviews", or each review should say "Goodreads review from John: 4 of 5 stars..."

TODO: Link back to the page on Goodreads where the data data appears. For instance, if displaying a review, the name of the reviewer and a "more..." link at the end of the review must link back to the review detail page. You may not nofollow this link.
