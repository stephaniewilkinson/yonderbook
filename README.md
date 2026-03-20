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

## Goodreads Attribution

Per the [Goodreads API Terms](https://www.goodreads.com/api/terms), any page displaying Goodreads data must:

1. Clearly display the Goodreads name or logo where their data appears
2. Link back to the Goodreads page for each piece of data (book, review, author)
3. Not use `nofollow` on those links

How we comply: book titles link to their Goodreads page, and all pages showing Goodreads data include a "Book data from Goodreads" attribution.

## Routing

This app uses the [roda-route-list plugin.](https://github.com/jeremyevans/roda-route_list) This makes all the routes available in a /routes.json file.

## Creating a self-signed certificate

```
openssl req -x509 -out localhost.crt -keyout localhost.key \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=localhost' -extensions EXT -config <( \
   printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
