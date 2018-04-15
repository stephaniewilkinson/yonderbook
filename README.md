[ ![Codeship Status for stephaniewilkinson/bookmooch](https://app.codeship.com/projects/859f6a90-2275-0136-c761-0e1a22c436f6/status?branch=master)](https://app.codeship.com/projects/286021)

# Tools for Bookworms 📒

## Installation

$ git clone


$ bundle exec rackup


## Testing

$ ruby spec/spec.rb


## Set up db

```
createuser -U postgres bookmooch
createdb -U postgres -O bookmooch bookmooch_production
createdb -U postgres -O bookmooch bookmooch_test
createdb -U postgres -O bookmooch bookmooch_development
```
