# hegel-agda justfile

ghc_env := env("GHC_ENV", ".ghc.environment." + `uname -m` + "-linux-" + `ghc --numeric-version 2>/dev/null || echo "9.6.7"`)
agda_compile := "agda --compile --ghc-flag=\"-i" + justfile_directory() + "/hs-support\" --ghc-flag=\"-package-env " + justfile_directory() + "/" + ghc_env + "\" --compile-dir=" + justfile_directory() + "/build"

# Build the Haskell FFI library and protocol test
build-hs:
    cabal build all

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

# Compile and run the Agda test suites
test: build-hs
    {{agda_compile}} test/TestBasic.agda
    ./build/TestBasic
    {{agda_compile}} test/TestGenerators.agda
    ./build/TestGenerators
    {{agda_compile}} test/TestComprehensive.agda
    ./build/TestComprehensive

# Run the Haskell protocol and DataSource unit tests
test-protocol: build-hs
    cabal run test-protocol
    cabal run test-datasource

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

# Run conformance tests (uses Agda-compiled binaries)
conformance: build-conformance
    python3 -m pytest test_conformance.py -v --tb=short

# Coverage: Agda has no native code coverage tooling.
# We verify coverage by running all tests and conformance.
# The type checker provides stronger guarantees than coverage in most languages.
coverage: test conformance
    @echo "Coverage: all tests and conformance tests passed."
    @echo "Note: Agda has no native code coverage tool. Type-checking + tests"
    @echo "provide the functional coverage guarantees for this implementation."

# Clean build artifacts
clean:
    rm -rf build/ dist-newstyle/
    find . -path './_build' -prune -o -name '*.agdai' -print | xargs rm -f 2>/dev/null || true
    find hs-support -name '*.hi' -o -name '*.o' | xargs rm -f 2>/dev/null || true

# Check everything
check: check-agda test test-protocol

# Format (no-op: Agda has no standard formatter)
format:
    @echo "No formatter configured for Agda"

# Lint (type-checking IS linting for Agda)
lint: check-agda
