---
active: false
iteration: 2
session_id:
max_iterations: 0
language: Java
started_at: 2026-04-14T20:20:00Z
completed_at: 2026-04-14T22:35:00Z
---

Implement a Hegel property-based testing library in Java.

## Phase 1: API Design
- [x] Read implementation guide chapters
- [x] Decided API: JUnit 5 extension, `tc.draw(generator)`, fluent builder pattern, `Hegel.test()` entry point
- [x] Decided: TestCase parameter, Generator<T> interface, BasicGenerator<T>, builder methods for constraints

## Phase 2: Project Infrastructure
- [x] Maven pom.xml with JUnit 5, jackson-dataformat-cbor, CRC32 (stdlib)
- [x] justfile with targets: test, coverage, format, lint, check, conformance
- [x] Coverage tooling with JaCoCo — must exit non-zero when coverage below 100%
- [x] Verify: run `just coverage` and confirm it FAILS
- [x] .gitignore
- [x] Coverage exclusion ratchet

## Phase 3: Core Protocol
- [x] Packet read/write with CRC32 and CBOR encoding
- [x] Connection with background reader thread
- [x] Stream multiplexing
- [x] Session management (spawn hegel-core via uv)
- [x] Handshake
- [x] Protocol unit tests

## Phase 4: Test Runner and DataSource
- [x] DataSource interface abstracting protocol operations
- [x] ServerDataSource wrapping the protocol stream
- [x] Test runner (runTest, test_case loop, mark_complete)
- [x] TestCase.draw() backed by DataSource
- [x] Handle StopTest, assume(), note(), target()
- [x] Error injection tests (HEGEL_PROTOCOL_TEST_MODE)
- [x] Integration test: basic property test runs end-to-end

## Phase 5: Primitive Generators
- [x] Generator<T> interface with asBasic()
- [x] BasicGenerator<T> with schema + transform
- [x] integers, floats, booleans, text, binary
- [x] just, sampledFrom
- [x] map combinator
- [x] filter combinator
- [x] flatMap combinator

## Phase 6: Collection Generators
- [x] lists (basic path)
- [x] lists (non-basic path)
- [x] tuples (as Object[])
- [x] maps/dicts
- [x] oneOf
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
- [x] Error: stop_test_on_generate
- [x] Error: stop_test_on_mark_complete
- [x] Error: stop_test_on_collection_more
- [x] Error: stop_test_on_new_collection
- [x] Error: error_response
- [x] Error: empty_test

## Phase 8: Format Generators
- [x] emails, urls, domains
- [x] ip_addresses
- [x] dates, times, datetimes
- [x] fromRegex

## Phase 9: Quality and Documentation
- [x] Test utilities (HegelTestUtils: assertAllExamples, findAny, minimal, assertNoExamples)
- [x] README.md
- [x] Getting-started guide (in README.md Quick Start section)
- [x] All tests passing (218 tests)
- [x] `just coverage` passes with 100% coverage
- [x] `just check` passes
