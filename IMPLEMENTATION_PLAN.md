---
active: false
iteration: 3
session_id:
max_iterations: 0
language: Racket
started_at: 2026-04-14T21:32:00Z
---

Implement a Hegel property-based testing library in Racket.

## Phase 1: API Design
- [x] Read implementation guide chapters
- [x] Write test sketches showing desired API
- [x] Decide: test entry point (rackunit integration), value drawing (draw), generator construction (keyword args), control functions (assume/note), settings

## Phase 2: Project Infrastructure
- [x] justfile with targets: test, coverage, format, lint, check, conformance
- [x] Coverage tooling installed and `just coverage` wired up
- [x] .gitignore
- [x] info.rkt (package metadata)

## Phase 3: Core Protocol
- [x] Implement CRC32 in Racket
- [x] Implement wire protocol (packet read/write, CRC32, CBOR encoding)
- [x] Implement connection with demand-driven reader
- [x] Implement stream multiplexing
- [x] Implement global session singleton
- [x] Session cleanup using plumber
- [x] uv auto-download if not on PATH
- [x] Implement handshake
- [x] Protocol unit tests (packet round-trips, CRC32 validation)
- [x] `just coverage` passes for protocol code

## Phase 4: Test Runner and DataSource
- [x] Define DataSource struct (with function fields)
- [x] Implement ServerDataSource
- [x] Implement test runner (run-hegel, test_case loop, mark-complete)
- [x] TestCase takes a DataSource
- [x] Handle StopTest correctly
- [x] Handle reply envelope format ({"result": value})
- [x] Implement assume, note
- [x] Integration test: basic property test runs end-to-end
- [x] Error injection tests using HEGEL_PROTOCOL_TEST_MODE
- [x] `just coverage` passes for runner code

## Phase 5: Primitive Generators
- [x] Implement generator struct with draw-fn and as-basic-fn
- [x] Implement basic-generator with schema + transform
- [x] integers, floats, booleans, text, binary
- [x] just, sampled-from
- [x] map combinator (preserves basicness on basic generators)
- [x] filter combinator (always non-basic, FILTER span)
- [x] flat-map combinator (always non-basic, FLAT_MAP span)

## Phase 6: Collection Generators
- [x] lists (basic path: schema composition)
- [x] lists (non-basic path: collection protocol)
- [x] tuples
- [x] dicts/hashmaps
- [x] one-of (all three paths)
- [x] optional

## Phase 7: Conformance Tests
- [x] Boolean conformance binary + passing
- [x] Integer conformance binary + passing
- [x] Float conformance binary + passing
- [x] Text conformance binary + passing
- [x] Binary conformance binary + passing
- [x] SampledFrom conformance binary + passing
- [x] List conformance binary + passing
- [x] Dict conformance binary + passing
- [x] Error handling: stop_test_on_generate
- [x] Error handling: stop_test_on_mark_complete
- [x] Error handling: stop_test_on_collection_more
- [x] Error handling: stop_test_on_new_collection
- [x] Error handling: error_response
- [x] Error handling: empty_test

## Phase 8: Format Generators
- [x] emails, urls, domains
- [x] ip-addresses (ipv4, ipv6)
- [x] dates, times, datetimes
- [x] from-regex

## Phase 9: Quality and Documentation
- [x] README.md
- [x] Getting-started guide (doc comment in main.rkt)
- [x] LICENSE file (MIT)
- [x] .claude/CLAUDE.md
- [x] .gitignore covers build artifacts
- [x] All tests passing (216 tests)
- [x] All conformance tests passing (14/14)
- [x] `just coverage` passes with 100% library coverage
- [x] `just check` passes
