---
active: true
iteration: 1
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
- [ ] justfile with targets: test, coverage, format, lint, check, conformance
- [ ] Coverage tooling installed and `just coverage` wired up
- [ ] Verify: run `just coverage` and confirm it FAILS (since there are no tests yet)
- [ ] .gitignore
- [ ] info.rkt (package metadata)

## Phase 3: Core Protocol
- [ ] Implement CRC32 in Racket
- [ ] Implement wire protocol (packet read/write, CRC32, CBOR encoding)
- [ ] Implement connection with demand-driven reader
- [ ] Implement stream multiplexing
- [ ] Implement global session singleton
- [ ] Session cleanup using plumber
- [ ] Server stderr redirected to `.hegel/server.{pid}.log`
- [ ] uv auto-download if not on PATH
- [ ] Implement handshake
- [ ] Protocol unit tests (packet round-trips, CRC32 validation)
- [ ] `just coverage` passes for protocol code

## Phase 4: Test Runner and DataSource
- [ ] Define DataSource struct (with function fields)
- [ ] Implement ServerDataSource
- [ ] Implement test runner (run-hegel, test_case loop, mark-complete)
- [ ] TestCase takes a DataSource
- [ ] Handle StopTest correctly
- [ ] Handle reply envelope format ({"result": value})
- [ ] Implement assume, note, target
- [ ] Integration test: basic property test runs end-to-end
- [ ] Error injection tests using HEGEL_PROTOCOL_TEST_MODE
- [ ] `just coverage` passes for runner code

## Phase 5: Primitive Generators
- [ ] Implement generator struct with draw-fn and as-basic-fn
- [ ] Implement basic-generator with schema + transform
- [ ] integers, floats, booleans, text, binary
- [ ] just, sampled-from
- [ ] map combinator (preserves basicness on basic generators)
- [ ] filter combinator (always non-basic, FILTER span)
- [ ] flat-map combinator (always non-basic, FLAT_MAP span)

## Phase 6: Collection Generators
- [ ] lists (basic path: schema composition)
- [ ] lists (non-basic path: collection protocol)
- [ ] tuples
- [ ] dicts/hashmaps
- [ ] one-of (all three paths)
- [ ] optional

## Phase 7: Conformance Tests
- [ ] Boolean conformance binary + passing
- [ ] Integer conformance binary + passing
- [ ] Float conformance binary + passing
- [ ] Text conformance binary + passing
- [ ] Binary conformance binary + passing
- [ ] SampledFrom conformance binary + passing
- [ ] List conformance binary + passing (both basic and non_basic modes)
- [ ] Dict conformance binary + passing (both basic and non_basic modes)
- [ ] Error handling: stop_test_on_generate
- [ ] Error handling: stop_test_on_mark_complete
- [ ] Error handling: stop_test_on_collection_more
- [ ] Error handling: stop_test_on_new_collection
- [ ] Error handling: error_response
- [ ] Error handling: empty_test

## Phase 8: Format Generators
- [ ] emails, urls, domains
- [ ] ip-addresses (ipv4, ipv6)
- [ ] dates, times, datetimes
- [ ] from-regex

## Phase 9: Quality and Documentation
- [ ] Test utilities (assert-all-examples, find-any, minimal, assert-no-examples)
- [ ] Shrink quality tests
- [ ] README.md
- [ ] Getting-started guide
- [ ] LICENSE file (MIT)
- [ ] .claude/CLAUDE.md
- [ ] .gitignore covers ALL build artifacts
- [ ] All tests passing
- [ ] All conformance tests passing
- [ ] `just coverage` passes with 100% coverage
- [ ] `just check` passes
