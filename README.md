[ ![Codeship Status for stephaniewilkinson/bookmooch](https://app.codeship.com/projects/859f6a90-2275-0136-c761-0e1a22c436f6/status?branch=master)](https://app.codeship.com/projects/286021)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/b69966957416487bafd98162e8179c3b)](https://app.codacy.com/app/stephaniewilkinson/yonderbook?utm_source=github.com&utm_medium=referral&utm_content=stephaniewilkinson/yonderbook&utm_campaign=badger)

# Yonderbook | Tools for Bookworms 📒
## Installation

```
git clone git@github.com:stephaniewilkinson/bookmooch.git
cd bookmooch
cp .env-example .env # if you msg me I can share my api keys
rake db:create
rake db:migrate
rackup
```

## Testing

`rake`

TODO: Clearly display the Goodreads name or logo on any location where Goodreads data appears. For instance if you are displaying Goodreads reviews, they should either be in a section clearly titled "Goodreads Reviews", or each review should say "Goodreads review from John: 4 of 5 stars..."

TODO: Link back to the page on Goodreads where the data data appears. For instance, if displaying a review, the name of the reviewer and a "more..." link at the end of the review must link back to the review detail page. You may not nofollow this link.

## Routing

This app uses the [roda-route-list plugin.](https://github.com/jeremyevans/roda-route_list) This makes all the routes available in a /routes.json file.
