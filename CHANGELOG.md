# Changelog

## 1.1.2

### Fixed

- Enforce a maximum of 255 Choice options and 10 Score levels for named and ad-hoc questions.
- Generate Score stub probabilities between adjacent levels so their weighted mean matches the supplied score; reject out-of-range scores when generating probabilities.
- Preserve explicitly supplied stub probabilities and confidence.

### Changed

- Simplify response parsing to JSON number and string key types, and require a definition when parsing Choice answers.
- Read HTTP error details from `detail.message`; remove error-message redaction and truncation.

## 1.1.1

### Fixed

- Validate question types before calling the transport and reject malformed Choice and Score response fields with gem errors.
- Preserve HTTP error classes when an error body is not a JSON object.
- Resolve autoloaded scopes outside the registry lock; respect model scopes in validations and overridden field bindings in batches.
- Match stubs using definition identity, including scoped and ad-hoc Score levels with identical instructions.
- Snapshot mutable recording data and return independent replay responses.
- Redact API keys before truncating error details, including messages from JSON responses.

### Performance

- Reuse HTTP connections, retain at most four idle connections, and discard connections after failures, configuration changes, or a fork. Concurrent requests keep separate connections.
- Index replay requests while preserving the first matching recording and the existing tape format.
- Cache immutable definition metadata without changing public collection mutability or Ruby Data copying and serialization.
- Collapse only requested batch keys during pattern matching.
- Retain compiled definition metadata across garbage collection in a bounded cache.
- Cache parsed endpoints, avoid sorting replay lookup keys, and reduce allocations in model bindings and ActiveModel validations.
- Index named Score levels when building stub probabilities.

## 1.1.0

### Added

- `Jev.define` accepts `choices:` (`decide`) and `levels:` (`score`, Hash, low to high).
- `Jev.decide`, `Jev.score`, `Jev.measure`, and `Jev.match`.
- Typed results: `Jev::Result::Noul`, `Jev::Result::Choice`, `Jev::Result::Score`, `Jev::Result::Batch`.
- Batch `Jev.measure(state) { |q| ... }` — one request, defined names only.
- `at_least:` on `feels?` (true / false / nil) and `confidence:` on `decide` / `match`.
- Native `case`/`in` on a batch via collapsed values.
- `Jev::Model`: `feels` / `decide` / `score` bind a field; instance `feels?`, `decide`, `score`, `measure`, `match`.
- Optional `require "feels/active_model"` and `validates_feeling`.
- `Jev.stub`, `Jev.record`, and `Jev.replay`. Tapes omit API keys.
- Opt-in String refinement / extension: `decide`, `score`, `measure`.

### Changed

- `feels` / `feels?` / `decide` / `score` collapse a typed `Jev.measure` result.
- Yes/no `Jev.definition` / `Jev.definitions` still return the instruction string. `choices:` / `levels:` return `Jev::Definition`.

## 1.0.0

- Initial `Jev.define` / `Jev.feels` / `Jev.feels?` API, injectable transport, and opt-in String sugar.
