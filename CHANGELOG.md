# Changelog

## 0.1.0 - 2026-04-14

Initial release of hegel-racket.

### Generators

- `(integers #:min-value ... #:max-value ...)` — generate exact integers with optional bounds
- `(floats #:min-value ... #:max-value ... #:exclude-min ... #:exclude-max ... #:allow-nan ... #:allow-infinity ...)` — generate flonums with optional bounds and special-value control
- `(booleans #:p ...)` — generate booleans with optional bias probability
- `(text #:min-size ... #:max-size ...)` — generate Unicode strings
- `(binary #:min-size ... #:max-size ...)` — generate byte strings
- `(just value)` — always return a fixed value
- `(sampled-from lst)` — pick uniformly from a fixed list
- `(lists elem-gen #:min-size ... #:max-size ... #:unique ...)` — generate lists; uses schema composition when element generator is basic
- `(tuples gen ...)` — generate fixed-length lists from multiple generators
- `(hashmaps key-gen val-gen #:min-size ... #:max-size ...)` — generate hash tables
- `(dicts key-gen val-gen #:min-size ... #:max-size ...)` — alias for `hashmaps`
- `(one-of gen ...)` — pick uniformly from multiple generators
- `(optional gen)` — generate `#f` or a value from gen
- `(emails)`, `(urls)`, `(domains)` — generate format-valid strings
- `(ipv4-addresses)`, `(ipv6-addresses)`, `(ip-addresses)` — generate IP address strings
- `(dates)`, `(times)`, `(datetimes)` — generate ISO 8601 date/time strings
- `(from-regex pattern)` — generate strings matching a regex
- `(generator-map gen proc)`, `(generator-filter gen pred?)`, `(generator-flat-map gen proc)` — combinators

### Core API

- `(run-hegel proc #:test-cases N #:seed S #:derandomize B #:database P #:suppress-health-check L)` — run a property test
- `(draw tc gen)` — draw a value from a generator inside a test case
- `(draw-silent tc gen)` — draw without span tracking (for internal use)
- `(tc-assume tc condition)` — skip test case if condition is `#f`
- `(tc-note tc message)` — record a note shown during the final shrunk replay

### Protocol

- Full Hegel wire protocol (CBOR over framed stdin/stdout pipes with CRC32)
- Stream-multiplexed connection with demand-driven reader thread
- Global session singleton per process with plumber-based cleanup on exit
- uv auto-discovery for hegel-core subprocess
