# Yonderbook — agent notes

## Fathom Analytics

The API token lives at `~/.config/fathom/token` (mode 600, outside every repo).
It is one **account-wide** token covering Yonderbook, Launchpad and Tectonic, so
it is deliberately not duplicated into any `.env` — one file, one rotation point,
and no chance of committing it. This repo has no `.env` at all, only
`.env-example`, so adding one purely for this would have been a new place for a
secret to live.

Read it as a bare value, stripping whitespace:

```bash
TOKEN=$(tr -d '[:space:]' < ~/.config/fathom/token)
curl -s -H "Authorization: Bearer $TOKEN" https://api.usefathom.com/v1/sites
```

**This project's site ID is `YKRZHUNU`.** Confirmed against the API on
2026-08-28, and on 2026-11-10 against the `data-site` the app renders
(`views/layout.erb`), with the API returning visits for it. Worth re-checking if
the snippet changes: one pointing at the wrong site collects nothing and looks
identical to one that works.

Aggregations, e.g. pageviews since a date:

```bash
curl -s -G https://api.usefathom.com/v1/aggregations \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "entity=pageview" \
  --data-urlencode "entity_id=YKRZHUNU" \
  --data-urlencode "aggregates=pageviews,visits,uniques" \
  --data-urlencode "date_from=2026-08-01"
```

Do not echo the token, paste it into a conversation, or write it into a file
inside this repo. It is account-wide: a leak exposes all three projects'
analytics and, depending on scope, site management.
