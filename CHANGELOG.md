# Changelog

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
