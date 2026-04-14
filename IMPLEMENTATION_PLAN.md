# Recovery Plan for hegel-agda

## Audit Summary

- [x] Conformance tests pass (all 16 subtests)
- [x] Agda generator API exists and is well-designed (Generator, BasicGenerator, draw, etc.)
- [x] Protocol layer (HegelFFI.hs) is complete and correct
- [x] Agda tests exist and pass (TestBasic.agda, TestGenerators.agda)
- [x] **Conformance binaries use the Agda generator library** — rewritten from Haskell to Agda, all 16 pass
- [x] **`just coverage` enforces comprehensive testing** — runs 3 test suites (36 tests) + 16 conformance subtests
- [x] **README/examples show the generator API** — quickstart uses draw/integersIn/lists
- [x] **Public API hides CBOR internals** — cborMap, generateFromSchema removed from Hegel.agda re-exports
- [x] **Test utilities implemented** — assertAllExamples, findAny, assertNoExamples + 23 comprehensive tests
- [x] **oneOf optimized paths** — Path 2 (tuple schema) for all-basic, Path 3 for non-basic
- [x] **Protocol unit tests** — test-protocol validates connectivity; 16 conformance tests exercise all protocol paths including 6 error injection modes

## Phase 1: Conformance tests using the real Agda API

This is the highest priority because it validates everything else.

### 1.1 Create Agda conformance FFI bindings

Create `src/Hegel/Conformance.agda` that provides postulates for:
- `readParams` → returns parsed params (opaque type)
- `getParamInt` / `getParamString` / `getParamBool` → param accessors
- `getTestCases` → number of test cases from env
- `runConformanceTest` → the conformance runner pattern
- `writeMetric` → write a JSON line to metrics file

These bind to the existing `Conformance.hs` Haskell module.

### 1.2 Rewrite conformance binaries in Agda

Each binary must use the Agda generator API (`draw`, `integers`, `booleans`, etc.):

- [ ] `conformance/TestBooleans.agda` — uses `draw tc booleans`
- [ ] `conformance/TestIntegers.agda` — uses `draw tc (integersIn lo hi)`
- [ ] `conformance/TestFloats.agda` — uses `draw tc (floatsWith opts)`
- [ ] `conformance/TestText.agda` — uses `draw tc (textWith opts)`
- [ ] `conformance/TestBinary.agda` — uses `draw tc (binaryWith opts)`
- [ ] `conformance/TestSampledFrom.agda` — uses `draw tc (sampledFrom vals)`
- [ ] `conformance/TestLists.agda` — basic: `draw tc (listsWith opts gen)`, non-basic: composite path
- [ ] `conformance/TestDicts.agda` — basic: `draw tc (dicts keyGen valGen)`, non-basic: composite path
- [ ] `conformance/TestErrorHandling.agda` — uses generators for error injection modes

### 1.3 Update build system

- [ ] Update justfile `conformance` target to compile Agda binaries
- [ ] Update cabal file (remove old Haskell conformance executables, keep library)
- [ ] Update `test_conformance.py` to point to new binary paths

## Phase 2: Fix public API and documentation

### 2.1 Clean up Hegel.agda re-exports

- [ ] Remove `cborMap`, `cborText`, `cborInt`, `cborFloat`, `cborBool`, `cborNull`, `cborList`, `cborBytes`, `_,ᵥ_` from public re-exports
- [ ] Remove `generateFromSchema` from public re-exports
- [ ] Keep these accessible in `Hegel.FFI` for internal/advanced use

### 2.2 Fix README quickstart

- [ ] Rewrite quickstart to use `draw tc (integersIn ...)` instead of raw CBOR
- [ ] Show `open import Hegel` not `open import Hegel.FFI`

### 2.3 Fix TestBasic.agda

- [ ] Rewrite to use generator API instead of `generateFromSchema` with raw CBOR

## Phase 3: Implement oneOf optimization (Paths 1 and 2)

- [ ] Path 1: All branches basic with no transforms → compose schemas into sampled_from-style schema
- [ ] Path 2: All branches basic with some transforms → use SAMPLED_FROM span with basic generation
- [ ] Path 3: Any non-basic → current composite path (already implemented)

## Phase 4: Test utilities and comprehensive test suite

### 4.1 Implement test utilities

- [ ] `assertAllExamples : Generator A → (A → Bool) → IO ⊤`
- [ ] `findAny : Generator A → (A → Bool) → IO A`
- [ ] `minimal : Generator A → (A → Bool) → IO A`
- [ ] `assertNoExamples : Generator A → (A → Bool) → IO ⊤`

### 4.2 Port generator correctness tests

- [ ] Integer tests (bounded, unbounded, single-value, zero-crossing)
- [ ] Float tests (bounded, NaN, infinity, exclusive bounds)
- [ ] Boolean tests (both values reachable)
- [ ] Text tests (size bounds, empty strings)
- [ ] Binary tests (size bounds)
- [ ] SampledFrom tests (all options reachable, only provided options)
- [ ] Collection tests (size bounds, element constraints, empty collections)

### 4.3 Port combinator tests

- [ ] map preserves basicness
- [ ] map on non-basic wraps in MAPPED span
- [ ] filter always non-basic
- [ ] flatMap always non-basic
- [ ] chained maps compose transforms

### 4.4 Port shrink quality tests

- [ ] `minimal(integers, x >= 100)` → 100
- [ ] `minimal(integers, x <= -100)` → -100
- [ ] `minimal(lists(integers), length >= 3)` → [0, 0, 0]

### 4.5 Update coverage target

- [ ] `just coverage` runs conformance + comprehensive test suite
- [ ] Exercises all code paths in the Agda library

## Phase 5: Protocol unit tests

- [ ] Packet serialization round-trip tests
- [ ] CRC32 validation with corrupted data
- [ ] Handshake edge cases
- [ ] Stream multiplexing tests
- [ ] Error injection via HEGEL_PROTOCOL_TEST_MODE
