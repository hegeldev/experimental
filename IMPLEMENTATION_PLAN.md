---
active: true
iteration: 1
session_id:
max_iterations: 0
language: Java
started_at: 2026-04-14T20:20:00Z
---

Implement a Hegel property-based testing library in Java.

## Phase 1: API Design
- [x] Read implementation guide chapters
- [x] Decided API: JUnit 5 extension, `tc.draw(generator)`, fluent builder pattern, `Hegel.test()` entry point
- [x] Decided: TestCase parameter, Generator<T> interface, BasicGenerator<T>, builder methods for constraints

## Phase 2: Project Infrastructure
- [ ] Maven pom.xml with JUnit 5, jackson-dataformat-cbor, CRC32 (stdlib)
- [ ] justfile with targets: test, coverage, format, lint, check, conformance
- [ ] Coverage tooling with JaCoCo — must exit non-zero when coverage below 100%
- [ ] Verify: run `just coverage` and confirm it FAILS
- [ ] .gitignore
- [ ] Coverage exclusion ratchet

## Phase 3: Core Protocol
- [ ] Packet read/write with CRC32 and CBOR encoding
- [ ] Connection with background reader thread
- [ ] Stream multiplexing
- [ ] Session management (spawn hegel-core via uv)
- [ ] Handshake
- [ ] Protocol unit tests

## Phase 4: Test Runner and DataSource
- [ ] DataSource interface abstracting protocol operations
- [ ] ServerDataSource wrapping the protocol stream
- [ ] Test runner (runTest, test_case loop, mark_complete)
- [ ] TestCase.draw() backed by DataSource
- [ ] Handle StopTest, assume(), note(), target()
- [ ] Error injection tests (HEGEL_PROTOCOL_TEST_MODE)
- [ ] Integration test: basic property test runs end-to-end

## Phase 5: Primitive Generators
- [ ] Generator<T> interface with asBasic()
- [ ] BasicGenerator<T> with schema + transform
- [ ] integers, floats, booleans, text, binary
- [ ] just, sampledFrom
- [ ] map combinator
- [ ] filter combinator
- [ ] flatMap combinator

## Phase 6: Collection Generators
- [ ] lists (basic path)
- [ ] lists (non-basic path)
- [ ] tuples (as Object[])
- [ ] maps/dicts
- [ ] oneOf
- [ ] optional

## Phase 7: Conformance Tests
- [ ] Boolean conformance binary + passing
- [ ] Integer conformance binary + passing
- [ ] Float conformance binary + passing
- [ ] Text conformance binary + passing
- [ ] Binary conformance binary + passing
- [ ] SampledFrom conformance binary + passing
- [ ] List conformance binary + passing
- [ ] Dict conformance binary + passing
- [ ] Error: stop_test_on_generate
- [ ] Error: stop_test_on_mark_complete
- [ ] Error: stop_test_on_collection_more
- [ ] Error: stop_test_on_new_collection
- [ ] Error: error_response
- [ ] Error: empty_test

## Phase 8: Format Generators
- [ ] emails, urls, domains
- [ ] ip_addresses
- [ ] dates, times, datetimes
- [ ] fromRegex

## Phase 9: Quality and Documentation
- [ ] Test utilities
- [ ] README.md
- [ ] Getting-started guide
- [ ] All tests passing
- [ ] `just coverage` passes with 100% coverage
- [ ] `just check` passes
