# jev-feels

Semantic checks as ordinary Ruby conditions.

```ruby
# Gemfile
gem "jev-feels"

require "feels"

Jev.configure do |config|
  config.api_key = ENV.fetch("JEV_API_KEY")
end

Jev.define :urgent, "Requires immediate attention or action"

email = <<~EMAIL
  Our production server has stopped responding.
  Customers cannot access their accounts.
  Please investigate immediately.
EMAIL

if Jev.feels?(email, :urgent)
  puts "URGENT"
end
```

## Ruby on Rails

Configure once, declare predicates on the model, ask the record:

```ruby
# Gemfile
gem "jev-feels"
```

```ruby
# config/initializers/jev.rb
Jev.configure do |config|
  config.api_key = ENV.fetch("JEV_API_KEY")
end
```

```ruby
class SupportEmail < ApplicationRecord
  include Jev::Model

  feels :body, :urgent, "Outage, customers cannot sign in"
end

email.feels?(:urgent)
email.feels(:urgent)
```

The class is the scope, the first argument is the field. No model name, no `email.body.feels?`.

String sugar is still opt-in (`using Jev::Feels` or `require "jev-feels/string"`) if you want `body.feels?(:urgent)` on a raw string.

## String sugar

`require "feels"` does not change `String`. Opt in with a refinement:

```ruby
using Jev::Feels

email.feels?(:urgent)
```

Or, if you really want a global patch:

```ruby
require "feels/string"
# or: require "jev-feels/string"

email.feels?(:urgent)
```

## Probability vs predicate

```ruby
email.feels(:urgent)
# => 0.94

email.feels?(:urgent)
# => true
```

`feels` is the calibrated probability that the predicate holds (a Jev [Noul](https://docs.typesafe.ai/primitives/noul.md), `0.0..1.0`).
`feels?` is `feels >= threshold`. The default threshold is `0.5`.

```ruby
email.feels?(:urgent, threshold: 0.8)
```

## Ad-hoc predicates

A `String` predicate is used as-is and is **not** registered:

```ruby
email.feels?("sounds like the sender is about to cancel their subscription")
```

A `Symbol` must already have a definition or you get `Jev::UndefinedDefinition`.

## Definitions

```ruby
Jev.define :urgent, "Requires immediate attention or action"
Jev.define :spam, "Unsolicited or unwanted promotional content"
Jev.define :angry, "Expresses anger or hostility"

Jev.define Email, :urgent, "Outage, customers cannot sign in"
Jev.define Comment, :urgent, "Legal takedown or self-harm"

Jev.definition(:urgent)
Jev.definition(Email, :urgent)
Jev.definitions
Jev.definitions(Comment)
```

`define` replaces an existing name in that scope. Scopes are stored by class name, so `Email`, `"Email"` and `:Email` are the same key. `include Jev::Model` plus `feels :body, :urgent, "..."` does the same define and remembers the field. `Jev.feels?(text, Email, :urgent)` uses Email's definition, then a superclass, then the global `:urgent`. `definitions` returns a frozen copy.

## Configuration

```ruby
Jev.configure do |config|
  config.api_key = ENV["JEV_API_KEY"]
  config.base_url = "https://api.typesafe.ai"
  config.timeout = 10
  config.threshold = 0.5
end
```

For tests, inject a transport and skip the network:

```ruby
Jev.configure do |config|
  config.transport = ->(_payload) {
    { "answers" => { "feels" => { "type" => "noul", "noul" => 0.9 } } }
  }
end
```

```ruby
Jev.reset_configuration!
Jev.reset_definitions!
```

## Errors

All errors inherit from `Jev::Error`. HTTP failures are wrapped; the original exception is available as `cause`. API keys are redacted from messages.

| Error | When |
| --- | --- |
| `Jev::ConfigurationError` | Missing API key |
| `Jev::UndefinedDefinition` | Unknown symbol predicate |
| `Jev::AuthenticationError` | HTTP 401 |
| `Jev::RateLimitError` | HTTP 429 |
| `Jev::InvalidResponseError` | Unparseable or shapeless body |
| `Jev::RequestError` | Timeouts, network errors, other HTTP failures |

## What this talks to

[Jev](https://docs.typesafe.ai/introduction.md) / TypeSafe System One. `POST https://api.typesafe.ai/v1/systemone` with a Noul question. That is an implementation detail of `feels`; the public API is just `Jev.feels` / `Jev.feels?`.
