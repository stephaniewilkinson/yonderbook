# Yonderbook | Tools for Bookworms 📒
## Installation

```
git clone git@github.com:stephaniewilkinson/yonderbook.git
cd yonderbook
cp .env-example .env # if you msg me I can share my api keys
rake db:create
rake db:migrate
```

## Start the Server
`falcon`

## Database Access

**Production (Render):**
```bash
sqlite3 /var/data/production.db
```

**Development:**
```bash
sqlite3 db/development.db
```

## Testing

`rake`

TODO: Clearly display the Goodreads name or logo on any location where Goodreads data appears. For instance if you are displaying Goodreads reviews, they should either be in a section clearly titled "Goodreads Reviews", or each review should say "Goodreads review from John: 4 of 5 stars..."

TODO: Link back to the page on Goodreads where the data data appears. For instance, if displaying a review, the name of the reviewer and a "more..." link at the end of the review must link back to the review detail page. You may not nofollow this link.

## BookMooch API

[BookMooch](https://bookmooch.com) is a book trading community where users can give away books they no longer need and receive books they want.

### Rate Limits

The BookMooch API allows up to **10 requests/second**. Exceeding this results in 302 redirect responses (not standard 429s). In practice, keeping requests concurrent with a connection pool limit (rather than throttling with a rate limiter) works best — a leaky bucket limiter causes timeouts and connection issues with BookMooch's server.

### GET vs POST

All API calls accept parameters via either GET (URL params) or POST (body). **Use POST for large payloads** like bulk ASIN/ISBN submissions — GET has a ~2048 character URL limit, so large ISBN lists must be batched. POST can send arbitrarily large fields in a single request.

### Error Handling

Errors are indicated by a negative `result_code` field in the XML response, with a `result_text` description:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<userids>
  <userid>
    <id>john_smith</id>
    <result_code>-1</result_code>
    <result_text>no data found</result_text>
  </userid>
</userids>
```

### Authentication

The `/api/userbook` endpoint uses HTTP Basic Auth. A 302 response means rate limiting; a 401 or HTML error page means invalid credentials (users should use their BookMooch username, not email).

## Routing

This app uses the [roda-route-list plugin.](https://github.com/jeremyevans/roda-route_list) This makes all the routes available in a /routes.json file.

## Creating a self-signed certificate

```
openssl req -x509 -out localhost.crt -keyout localhost.key \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=localhost' -extensions EXT -config <( \
   printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
