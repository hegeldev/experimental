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

### 1.1 Create Agda conformance FFI bindings

- [x] Created `src/Hegel/Conformance.agda` with FFI postulates for Params, MetricsWriter, param accessors, runConformance, utility functions
- [x] Added `MetricsWriter`, `runConformanceAgda`, `paramStringList` to `hs-support/Conformance.hs`

### 1.2 Rewrite conformance binaries in Agda

- [x] `conformance/TestBooleans.agda` — uses `draw tc booleans`
- [x] `conformance/TestIntegers.agda` — uses `draw tc (integersWith opts)`
- [x] `conformance/TestFloats.agda` — uses `draw tc (floatsWith opts)`
- [x] `conformance/TestText.agda` — uses `textWith opts` schema + `valueToCodepoints` for WTF-8
- [x] `conformance/TestBinary.agda` — uses `draw tc (binaryWith opts)`
- [x] `conformance/TestSampledFrom.agda` — uses `draw tc (sampledFrom vals)`
- [x] `conformance/TestLists.agda` — basic: `listsWith opts gen`, non-basic: composite wrapper
- [x] `conformance/TestDicts.agda` — basic: `dictsWith opts keyGen valGen`, non-basic: composite wrapper
- [x] `conformance/TestErrorHandling.agda` — uses generators for error injection modes

### 1.3 Update build system

- [x] Update justfile `conformance` target to compile Agda binaries via `agda --compile`
- [x] Update cabal file (removed old Haskell conformance executables, kept library + test-protocol)
- [x] Update `test_conformance.py` to point to `build/` directory

## Phase 2: Fix public API and documentation

### 2.1 Clean up Hegel.agda re-exports

- [x] Removed `cborMap`, `cborText`, `cborInt`, `cborFloat`, `cborBool`, `cborNull`, `cborList`, `cborBytes`, `_,ᵥ_` from public re-exports
- [x] Removed `generateFromSchema` from public re-exports
- [x] These remain accessible in `Hegel.FFI` for internal/advanced use

### 2.2 Fix README quickstart

- [x] Rewritten to use `draw tc (integersIn ...)` and `draw tc (lists booleans)`
- [x] Shows `open import Hegel` not `open import Hegel.FFI`

### 2.3 Fix TestBasic.agda

- [x] Rewritten to use `draw tc booleans`, `draw tc (integersIn ...)`, etc.

## Phase 3: Implement oneOf optimization (Paths 1 and 2)

- [x] Path 2: All branches basic → tuple schema `{"type": "tuple", "elements": [indexSchema, ...]}` for single round-trip
- [x] Path 3: Any non-basic → composite generation with ONE_OF span (unchanged)
- [x] Path 1 is N/A for Agda — all generators have transforms (CBOR Value → native type), so Path 2 always applies when all branches are basic
- [x] Updated `optional` to use basic first branch (`justGen + gmap`) for Path 2 optimization

## Phase 4: Test utilities and comprehensive test suite

### 4.1 Implement test utilities

- [x] `assertAllExamples : Generator A → (A → Bool) → IO Bool` — fails test on counterexample
- [x] `findAny : Generator A → (A → Bool) → IO Bool` — uses assertFail to trigger INTERESTING
- [x] `assertNoExamples : Generator A → (A → Bool) → IO Bool` — fails if any value satisfies condition

### 4.2 Port generator correctness tests (23 tests in TestComprehensive.agda)

- [x] Integer tests: bounds, single-value, zero-crossing, large values, negative values
- [x] Boolean tests: both values reachable
- [x] Text tests: empty strings
- [x] SampledFrom tests: all options reachable, only provided options
- [x] Collection tests: empty lists, min-size, tuples

### 4.3 Port combinator tests

- [x] map preserves basicness (testMapBasic)
- [x] map flips values (testMapNot)
- [x] filter restricts output (testFilterBasic)
- [x] flatMap produces dependent generation (testFlatMap)
- [x] oneOf with all basic — Path 2 (testOneOfBasic)
- [x] oneOf with non-basic — Path 3 (testOneOfComposite)
- [x] optional produces Nothing and Just (testOptionalNothing, testOptionalJust)
- [x] fromRegex generates matching strings (testFromRegex)

### 4.4 Update coverage target

- [x] `just coverage` runs test (3 suites, 36 tests) + conformance (16 subtests)
- [x] Exercises all code paths: basic/composite generators, collection protocol, error handling, combinators, format generators

## Phase 5: Protocol testing

- [x] test-protocol validates basic connectivity and generation via real server
- [x] Conformance tests exercise all protocol paths:
  - [x] Basic generation (BooleanConformance, IntegerConformance, FloatConformance, TextConformance, BinaryConformance)
  - [x] Schema composition — basic list/dict (ListConformance[basic], DictConformance[basic])
  - [x] Collection protocol — non-basic list/dict (ListConformance[non_basic], DictConformance[non_basic])
  - [x] StopTest on generate, mark_complete, collection_more, new_collection
  - [x] Error response handling
  - [x] Empty test (zero test cases)
