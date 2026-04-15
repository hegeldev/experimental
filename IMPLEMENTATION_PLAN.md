# Hegel-Java Recovery Plan

## Audit Summary (2026-04-15)

All 12 checks now PASS.

## Completed Items

- [x] Conformance tests (14/14 pass)
- [x] Conformance tests use library API (Generators + tc.draw)
- [x] Coverage enforcement (100% line, clean build, exits non-zero on failure)
- [x] API correctness (no CBOR/schema exposure)
- [x] Counterexample display (drawn values shown automatically on failure)
- [x] Test framework integration (@HegelTest JUnit 5 annotation)
- [x] Test utilities (assertAllExamples, assertNoExamples, findAny, minimal)
- [x] DataSource abstraction (interface + MockDataSource)
- [x] Protocol unit tests (Packet, Stream, Connection, CBOR)
- [x] Required files (README, LICENSE, CLAUDE.md, .gitignore, justfile)
- [x] Build and lint pass
- [x] Code quality (no TODOs, no dead code)

## Recovery Items (all completed)

### 1. Counterexample display on failure
- [x] Track drawn values in TestCase (list of label+value pairs)
- [x] On final shrunk replay, print all drawn values to stderr before the error
- [x] Added `draw(Generator, String)` labeled overload
- [x] Added `printDrawnValues()` and `drawnValues()` methods
- [x] Unit tests for all new code paths
- [x] 100% line coverage maintained

### 2. @HegelTest JUnit 5 extension
- [x] Created `@HegelTest` annotation with testCases, seed, derandomize attributes
- [x] Created `HegelExtension` (InvocationInterceptor + ParameterResolver)
- [x] Derives test name from method name; supports optional TestCase parameter
- [x] Added `junit-jupiter-api` as compile dependency
- [x] Unit tests for annotation usage, custom settings, and all error paths
- [x] Updated README to show @HegelTest as primary API
- [x] 100% line coverage maintained
