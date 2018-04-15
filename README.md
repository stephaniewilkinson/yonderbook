[![Build Status](https://travis-ci.org/stephaniewilkinson/bookmooch.svg?branch=master)](https://travis-ci.org/stephaniewilkinson/bookmooch)
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
