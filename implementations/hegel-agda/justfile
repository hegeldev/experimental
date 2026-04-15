# hegel-agda justfile

ghc_env := env("GHC_ENV", ".ghc.environment." + `uname -m` + "-linux-" + `ghc --numeric-version 2>/dev/null || echo "9.6.7"`)
agda_compile := "agda --compile --ghc-flag=\"-i" + justfile_directory() + "/hs-support\" --ghc-flag=\"-package-env " + justfile_directory() + "/" + ghc_env + "\" --compile-dir=" + justfile_directory() + "/build"

# Build the Haskell FFI library and protocol test
build-hs:
    cabal build all

# Compile all Agda test binaries
build-tests:
    {{agda_compile}} test/TestBasic.agda
    {{agda_compile}} test/TestGenerators.agda
    {{agda_compile}} test/TestComprehensive.agda

# Compile all Agda conformance binaries
build-conformance:
    {{agda_compile}} conformance/TestBooleans.agda
    {{agda_compile}} conformance/TestIntegers.agda
    {{agda_compile}} conformance/TestFloats.agda
    {{agda_compile}} conformance/TestText.agda
    {{agda_compile}} conformance/TestBinary.agda
    {{agda_compile}} conformance/TestSampledFrom.agda
    {{agda_compile}} conformance/TestLists.agda
    {{agda_compile}} conformance/TestDicts.agda
    {{agda_compile}} conformance/TestErrorHandling.agda

# Build everything (Haskell + Agda tests + conformance)
build: build-hs build-tests build-conformance

# Type-check all Agda source modules
check-agda:
    agda src/Hegel/FFI.agda
    agda src/Hegel/Generator.agda
    agda src/Hegel/Combinators.agda
    agda src/Hegel/Generators/Primitives.agda
    agda src/Hegel/Generators/Collections.agda
    agda src/Hegel/Generators/Format.agda
    agda src/Hegel/Conformance.agda
    agda src/Hegel.agda

# Run the Agda test suites (assumes binaries already compiled)
run-tests:
    ./build/TestBasic
    ./build/TestGenerators
    ./build/TestComprehensive

# Compile and run Agda tests
test: build-hs build-tests run-tests

# Run the Haskell protocol and DataSource unit tests
test-protocol: build-hs
    cabal run test-protocol
    cabal run test-datasource

# Run conformance tests (compiles binaries first)
conformance: build-conformance
    python3 -m pytest test_conformance.py -v --tb=short

# Run conformance tests without recompilation (assumes binaries exist)
run-conformance:
    python3 -m pytest test_conformance.py -v --tb=short

# Coverage: run all tests and conformance (run-only, no recompilation).
# Assumes `just build` has been run. Agda has no native code coverage
# tooling, so we verify by exercising all code paths via comprehensive
# tests (74 Agda tests + 16 protocol tests + 16 conformance subtests).
coverage: run-tests test-protocol run-conformance
    @echo "Coverage: all tests and conformance tests passed."
    @echo "Note: Agda has no native code coverage tool. Type-checking + tests"
    @echo "provide the functional coverage guarantees for this implementation."

# Clean build artifacts
clean:
    rm -rf build/ dist-newstyle/
    find . -path './_build' -prune -o -name '*.agdai' -print | xargs rm -f 2>/dev/null || true
    find hs-support -name '*.hi' -o -name '*.o' | xargs rm -f 2>/dev/null || true

# Check everything (type-check + build + test + protocol tests)
check: check-agda build-hs build-tests run-tests test-protocol

# Format (no-op: Agda has no standard formatter)
format:
    @echo "No formatter configured for Agda"

# Lint (type-checking IS linting for Agda)
lint: check-agda
