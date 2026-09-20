# jev-feels

Semantic decisions as ordinary Ruby.

```ruby
# Gemfile
gem "jev-feels"

require "feels"
using Jev::Feels

Jev.configure do |config|
  config.api_key = ENV.fetch("JEV_API_KEY")
end

Jev.define :urgent, "Requires immediate attention or action"

if email.body.feels?(:urgent)
  email.mark(:urgent)
end
```

The same idea continues for a decision and a scale:

```ruby
Jev.define :support_team,
  "Which team should handle this?",
  choices: {
    billing: "payments and refunds",
    technical: "bugs and outages",
    sales: "purchase questions",
    other: "none of the above"
  }

team = Jev.decide(email.body, :support_team)
```

```ruby
Jev.define :severity,
  "How severe is this issue?",
  levels: {
    minor: "minor inconvenience",
    degraded: "workaround exists",
    blocking: "cannot complete the task",
    critical: "major outage or severe impact"
  }

severity = Jev.score(email.body, :severity)
```

You do not need the Jev JSON wire format or the HTTP API for typical use. `Jev.measure` keeps the full typed result when you do.

## Ruby on Rails

Configure once, declare on the model, ask the record:

```ruby
# Gemfile
gem "jev-feels"
```

```ruby
# config/initializers/jev.rb
require "feels/active_model"

Jev.configure do |config|
  config.api_key = ENV.fetch("JEV_API_KEY")
end

Jev.define :urgent, "Requires immediate attention or action"
Jev.define :support_team, "Which team should handle this?", choices: {
  billing: "payments and refunds",
  technical: "bugs and outages",
  other: "none of the above"
}
```

```ruby
class SupportEmail < ApplicationRecord
  include Jev::Model

  feels :body, :urgent # Get definition from initializer
  feels :subject, :not_important, "Subject of this email is not important" # Or define in model
  decide :body, :support_team

  validates_feeling :body, :urgent, threshold: 0.9
end

email.feels?(:urgent)
email.feels?(:not_important)
email.decide(:support_team)
```

The class is the scope, the first argument is the field. `validates_feeling` accepts `allow_nil:`, `allow_blank:`, `if:`, `unless:`, `on:`, `message:`, `at_least:`. If those skip the check, there is no HTTP call. A `nil` from `at_least:` is a validation failure.

## String sugar

`require "feels"` does not change `String`. Opt in with a refinement:

```ruby
using Jev::Feels

email.body.feels?(:urgent)
email.body.decide(:support_team)
email.body.score(:severity)
```

Or, if you really want a global patch:

```ruby
require "feels/string"
# or: require "jev-feels/string"
```

## Definitions

`Jev.define` is the vocabulary of the app. A symbol without extras is a yes/no check:

```ruby
Jev.define :urgent, "Requires immediate attention or action"
Jev.define :spam, "Unsolicited or unwanted promotional content"
```

A decision (`decide`):

```ruby
Jev.define :support_team,
  "Which support team should handle this?",
  choices: {
    billing: "payments, invoices, charges and refunds",
    technical: "bugs, outages and integrations",
    sales: "purchase and plan questions",
    other: "none of the above"
  }
```

A scale (`score`). Hash order is low to high:

```ruby
Jev.define :severity,
  "How severe is this customer issue?",
  levels: {
    cosmetic: "minor visual or cosmetic issue",
    degraded: "functionality is degraded but a workaround exists",
    blocking: "the customer cannot complete an important task",
    critical: "major outage, data loss, security issue, or severe business impact"
  }
```

Scoped names still work:

```ruby
Jev.define Email, :urgent, "Outage, customers cannot sign in"
Jev.define Comment, :urgent, "Legal takedown or self-harm"

Jev.definition(:urgent)
Jev.definition(Email, :urgent)
Jev.definitions
Jev.definitions(Comment)
```

`define` replaces an existing name in that scope. Scopes are stored by class name, so `Email`, `"Email"` and `:Email` are the same key. A yes/no definition reads back as its instruction string. `choices:` / `levels:` read back as a `Jev::Definition`. On a Rails model, `feels` / `decide` / `score` bind a field; see [Ruby on Rails](#ruby-on-rails).

A `Symbol` must already have a definition or you get `Jev::UndefinedDefinition`. A `String` is an ad-hoc question and is not registered.

## Asking

```ruby
Jev.feels(email.body, :urgent)   # => 0.93
Jev.feels?(email.body, :urgent)  # => true / false
Jev.decide(ticket, :support_team) # => :billing
Jev.score(ticket, :severity)      # => 2.37
```

`feels` is the calibrated probability (`0.0..1.0`). `feels?` is `feels >= threshold`. The default threshold is `0.5`.

```ruby
email.body.feels?(:urgent, threshold: 0.8)
```

`decide` returns the winning Symbol. `score` returns the fractional ordinal position — not a percentage.

Ad-hoc questions skip `define`:

```ruby
email.body.feels?("sounds like the sender is about to cancel their subscription")

Jev.decide(
  ticket,
  "Which support team should handle this?",
  choices: {
    billing: "payments and refunds",
    technical: "bugs and outages",
    other: "none of the above"
  }
)
```

`Jev.feels?(text, Email, :urgent)` uses Email's definition, then a superclass, then the global `:urgent`.

## Uncertainty

`threshold:` is a single true/false cut. `0.51` and `0.99` are the same `true`.

`at_least:` is minimum certainty in either direction. The middle band is `nil`:

```ruby
text.feels?(:urgent, at_least: 0.8)
# p >= 0.8       => true
# p <= 0.2       => false
# 0.2 < p < 0.8  => nil
```

Without `at_least:`, `feels?` is still always true or false.

Do not pass both `threshold:` and `at_least:`.

`decide` uses confidence, which is not the winner's probability:

```ruby
Jev.decide(ticket, :support_team, confidence: 0.8)
# => :billing or nil
```

## Typed results

Convenience methods collapse a result. `measure` keeps the rest:

```ruby
result = Jev.measure(ticket, :urgent)
result.probability
result.type # => :noul

result = Jev.measure(ticket, :support_team)
result.choice
result.confidence
result.probabilities
result.type # => :choice

result = Jev.measure(ticket, :severity)
result.score
result.confidence
result.probabilities
result.levels
result.level # => :blocking
result.type  # => :score
```

```ruby
feels?  # boolean, or nil with at_least:
feels   # probability
decide  # Symbol, or nil with confidence:
score   # Float
```

## Batch

Several questions, one Jev request, one `state`:

```ruby
result = Jev.measure(ticket) do |q|
  q.feels :urgent
  q.feels :angry
  q.decide :support_team
  q.score :severity
end

result[:urgent]        # => Jev::Result::Noul
result[:support_team]  # => Jev::Result::Choice
result[:severity]      # => Jev::Result::Score

result.to_h
# => { urgent: true, angry: false, support_team: :billing, severity: 2.37 }
```

A batch only uses defined names. Ad-hoc strings stay on a single `feels?` / `decide` / `score`.

## Pattern matching

`Jev::Result::Batch` uses collapsed values. No extra HTTP calls:

```ruby
case Jev.measure(ticket) { |q|
  q.feels :urgent
  q.decide :support_team
  q.score :severity
}
in { urgent: true, support_team: :billing }
  escalate_billing(ticket)
in { support_team: :technical }
  route_to_technical(ticket)
in { urgent: true, severity: 2.0.. }
  escalate(ticket)
else
  manual_review(ticket)
end
```

`feels?` collapses to `true`/`false`, `decide` to a Symbol, `score` stays a Float so ranges work.

## `Jev.match`

A small dispatch for one `decide`. Low confidence goes to `otherwise`:

```ruby
Jev.match(ticket, :support_team) do
  on(:billing)   { route_to_billing(ticket) }
  on(:technical) { route_to_technical(ticket) }
  on(:sales)     { route_to_sales(ticket) }
  otherwise      { manual_review(ticket) }
end

Jev.match(ticket, :support_team, confidence: 0.8) do
  on(:billing, :sales) { route_to_commercial(ticket) }
  otherwise            { manual_review(ticket) }
end
```

## Tests: stub, record, replay

Stub by definition name. The block restores the previous transport, including in other threads:

```ruby
Jev.stub(
  urgent: 0.95,
  support_team: :billing,
  severity: 2.4
) do
  expect(ticket.feels?(:urgent)).to be(true)
  expect(Jev.decide(ticket, :support_team)).to eq(:billing)
end
```

A full `decide` / `score` stub is a hash with `choice` or `score`, plus `confidence` and `probabilities`. To own the HTTP shape, set `config.transport`.

Record real answers and replay them later. Replay never uses the network. The tape matches the request (state and questions), not a queue index. API keys and Authorization headers are not stored.

```ruby
tape = Jev.record do
  ticket.feels?(:urgent)
  Jev.decide(ticket, :support_team)
end

json = tape.to_json

Jev.replay(tape) do
  ticket.feels?(:urgent)
  Jev.decide(ticket, :support_team)
end
```

```ruby
Jev.reset_configuration!
Jev.reset_definitions!
```

## Configuration

```ruby
Jev.configure do |config|
  config.api_key = ENV["JEV_API_KEY"]
end
```

`base_url` defaults to `https://api.typesafe.ai`, `timeout` to 10 seconds, `threshold` to `0.5`. Override only if you need to.

## Errors

All errors inherit from `Jev::Error`. HTTP failures are wrapped; the original exception is available as `cause`. API keys are redacted from messages.

| Error                       | When                                          |
| --------------------------- | --------------------------------------------- |
| `Jev::ConfigurationError`   | Missing API key                               |
| `Jev::UndefinedDefinition`  | Unknown symbol predicate                      |
| `Jev::AuthenticationError`  | HTTP 401                                      |
| `Jev::RateLimitError`       | HTTP 429                                      |
| `Jev::InvalidResponseError` | Unparseable or shapeless body                 |
| `Jev::RequestError`         | Timeouts, network errors, other HTTP failures |
| `Jev::ReplayError`          | Replay tape does not contain this request     |

Malformed definitions (`choices:` and `levels:` together, empty Choice, too few Score levels, duplicate keys, invalid `threshold:` / `at_least:` / `confidence:`) raise `ArgumentError`.

## What this talks to

[Jev](https://docs.typesafe.ai/introduction.md) / TypeSafe System One. `POST https://api.typesafe.ai/v1/systemone`. That is an implementation detail. The public API is `Jev.feels` / `Jev.feels?` / `Jev.decide` / `Jev.score` / `Jev.measure` / `Jev.match`.