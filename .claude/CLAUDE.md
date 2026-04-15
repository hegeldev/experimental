# hegel-racket

Hegel property-based testing library for Racket.

## Build commands

```bash
just test        # run all unit tests (raco test tests/) — fast, no coverage
just coverage    # raco cover + coverage-check.py (must be 100% library coverage)
just lint        # raco make: check all files compile cleanly
just format      # raco expand: check all source files parse cleanly
just conformance # pytest against hegel-core==0.4.0 (uv run --with)
just check       # coverage + lint + conformance (full gate)
```

## Architecture

### Source layout

| File | Role |
|---|---|
| `protocol.rkt` | Wire protocol: packet framing (HEGL magic, CRC32, CBOR), `read-packet`/`write-packet` |
| `connection.rkt` | TCP-like multiplexed streams over stdin/stdout pipes; demand-driven reader thread |
| `session.rkt` | Global session singleton; spawns hegel-core subprocess, handshake, plumber cleanup |
| `test-case.rkt` | `TestCase` struct; `draw`, `tc-assume`, `tc-note`, `tc-start-span`, `tc-stop-span` |
| `runner.rkt` | `run-hegel`: event loop, StopTest handling, shrink replay, health check errors |
| `conformance.rkt` | Helpers for conformance binaries: `get-test-cases`, `write-metrics`, `make-non-basic` |
| `main.rkt` | Public re-export surface |
| `generators/core.rkt` | `generator` struct, `make-basic-generator`, `generator-as-basic`, combinators |
| `generators/numeric.rkt` | `integers`, `floats`, `booleans` |
| `generators/strings.rkt` | `text`, `characters`, `binary` |
| `generators/misc.rkt` | `just`, `sampled-from`, `one-of`, `optional` |
| `generators/collections.rkt` | `lists`, `sets`, `tuples`, `dicts`/`hashmaps` (basic + non-basic paths) |
| `generators/format.rkt` | `emails`, `urls`, `domains`, `ipv4-addresses`, `ipv6-addresses`, `ip-addresses`, `dates`, `times`, `datetimes`, `from-regex` |
| `test-utils.rkt` | `assert-all-examples`, `assert-no-examples`, `find-any`, `minimal` |

### Protocol

Packets: 20-byte header (`HEGL` magic, CRC32, stream_id, message_id, payload_length) + CBOR payload + `\n` terminator.

Stream 0 is the control stream. Odd stream IDs are client-initiated (test runs). Even stream IDs are server-initiated (callbacks during generation).

All strings from the server are wrapped in CBOR tag 91 (WTF-8 bytes).

### Session singleton

`session-box` in `session.rkt` holds a single `hegel-session` struct (connection + control-stream). Created lazily on first `run-hegel` call. Cleaned up on process exit via `plumber-add-flush!`. Tests that need a fresh session use `reset-session-for-testing!`.

### Basic vs. non-basic generators

A "basic" generator has a pure CBOR schema and an optional transform function. The schema is sent to the server in a `generate` command; the server returns the value directly.

A "non-basic" generator uses the collection protocol: `new_collection` to start, `collection_more` to check if more elements are needed, `collection_reject` to discard duplicates. This is used for filtered generators, flat-map, and lists with `#:unique #t`.

`generator-as-basic` returns `#f` for non-basic generators. Collection generators check this and fall through to the non-basic path if needed.

## Testing conventions

### Unit tests

- `tests/test-protocol.rkt` — packet encode/decode, CRC32
- `tests/test-connection.rkt` — stream multiplexing, reader thread
- `tests/test-runner.rkt` — event loop branches (mock data sources)
- `tests/test-generators.rkt` — generator construction, map/filter/flat-map
- `tests/test-session.rkt` — parse-version, find-uv, hegel-command, init-session error paths
- `tests/test-conformance-helpers.rkt` — get-test-cases, write-metrics, make-non-basic
- `tests/test-integration.rkt` — end-to-end tests using real hegel-core; mock server tests

### Mock server

`tests/mock-server.py` is a Python script that speaks the Hegel protocol. Set `HEGEL_SERVER_COMMAND` to point to it and `MOCK_SERVER_MODE` to control behavior:
- `health_check_failure`, `flaky` — server-side error modes
- `else_loop` — sends unknown event before test_done
- `missing_keys` — sends test_done without all keys
- `passed_false_no_replay` — passed=false with 0 interesting_test_cases

Use `reset-session-for-testing!` before/after mock server tests to avoid contaminating the real session.

### Coverage

`just coverage` runs `raco cover` then `coverage-check.py` which parses `coverage/index.html` and fails if any non-test library file is below 100%. The overall project percentage (98.99%) includes test files with some uncovered branches; that is expected and fine.

## Key gotchas

- `find-uv` takes an optional `locations` list. Pass `'()` in tests to force the `"uv"` fallback without touching the filesystem.
- `plumber-flush-all` (no `!`) is the correct Racket name for flushing all plumber handlers.
- Float conformance binary: JSON null `allow_nan` must use `json-bool->opt` (returns `'unset`), not `json-val->opt` (returns `#f`), because `(boolean? #f) = #t` would incorrectly treat null as false.
- The conformance binary `test_lists.rkt` reports `{size, min_element, max_element}` metrics for hegel-core 0.4.0; hegel-core 0.4.1 changed this to `{elements: [...]}`. The justfile pins 0.4.0.
- `just conformance` uses `uv run --with 'hegel-core==0.4.0'`, which is a separate environment from the tooling venv (which has 0.4.1). Always use `just conformance` to test, not `python3 -m pytest` directly.
- The Hypothesis example database is in `.hypothesis/`. Clear it with `rm -rf .hypothesis/examples/` if conformance tests get stuck on a cached failing example.
- `ip-addresses` uses `one-of (ipv4-addresses) (ipv6-addresses)` — hegel-core has no `"ip_address"` schema type.
- `from-regex` uses `"fullmatch"` key (not `"full_match"`) — the Hypothesis API key name.
- `lists` with `#:unique #t` and a basic element generator uses the basic schema path (`"unique": true` in the schema); only non-basic elements use the collection protocol for uniqueness.
- `sets` is `generator-map` of `lists(unique=#t)` and returns a Racket immutable set via `list->set`. Since `generator-map` on a basic generator preserves basicness, `sets (integers)` is basic.
- After source changes, delete `compiled/` directories if you see `instantiate-linklet: mismatch` errors (stale bytecode).
- CBOR bignums (integers ≥ 2^64 or below -2^63) require `cbor-default-config` as the base for `hegel-cbor-config`. Using `cbor-empty-config` causes the library to return raw `cbor-tag` structs instead of Racket exact integers for large values.
- In Racket, `#rx` does NOT support `{n}` quantifiers — those are PCRE-only. Use `#px` for patterns like `^[0-9]{4}-[0-9]{2}`. The `#rx` pattern silently returns `#f` instead of raising an error.
