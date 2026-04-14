---
active: true
iteration: 4
session_id: 
max_iterations: 0
language: Agda
started_at: 2026-04-14T13:26:59Z
---

Implement a Hegel property-based testing library in Agda.

## Phase 1: API Design
- [x] Read implementation guide chapters
- [x] Write test sketches showing desired API
- [x] Decide: test entry point, value drawing, generator construction, control functions, settings

## Phase 2: Project Infrastructure
- [x] justfile with targets: test, check, conformance
- [x] .gitignore
- [x] Build via Agda --compile with GHC backend

## Phase 3: Core Protocol
- [x] Wire protocol (packet read/write, CRC32, CBOR encoding) — hs-support/HegelFFI.hs
- [x] Connection with background reader thread
- [x] Stream multiplexing
- [x] Session management (spawn hegel-core via python3 -m hegel)
- [x] Handshake
- [x] StopTest handling
- [x] Integration test: Haskell test-protocol passes

## Phase 4: Test Runner
- [x] Test runner (run_test, test_case loop, mark_complete)
- [x] assume(), note(), target() FFI bindings
- [x] Integration test: TestBasic.agda runs 3 tests end-to-end

## Phase 5: Primitive Generators
- [x] Generator type with asBasic() — Hegel.Generator
- [x] BasicGenerator with schema + transform
- [x] integers, floats, booleans, text, binary — Hegel.Generators.Primitives
- [x] just, sampledFrom
- [x] map combinator (preserves basicness) — Hegel.Combinators
- [x] filter combinator (always non-basic, FILTER span)
- [x] flat_map combinator (always non-basic, FLAT_MAP span)
- [x] Test: TestGenerators.agda runs 10 tests (booleans, integersIn, text, listBasic, map, tuples, sampledFrom, oneOf, assume, floats)

## Phase 6: Collection Generators
- [x] lists (basic path: schema composition)
- [x] lists (non-basic path: collection protocol)
- [x] tuples
- [x] dicts
- [x] one_of (composite path)
- [x] optional

## Phase 7: Conformance Tests
- [x] Boolean conformance binary + passing
- [x] Integer conformance binary + passing
- [x] Float conformance binary + passing
- [ ] Text conformance binary (failing on server-side codec/codepoint filtering edge case)
- [x] Binary conformance binary + passing
- [x] SampledFrom conformance binary + passing
- [x] List conformance binary + passing (both basic and non_basic modes)
- [x] Dict conformance binary + passing (both basic and non_basic modes)

## Phase 8: Format Generators
- [x] emails, urls, domains
- [x] ip_addresses (ipv4, ipv6)
- [x] dates, times, datetimes
- [x] from_regex

## Phase 9: Quality and Documentation
- [x] README.md
- [x] CHANGELOG.md
- [ ] All conformance tests passing
