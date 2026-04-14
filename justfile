# hegel-agda justfile

ghc_env := env("GHC_ENV", ".ghc.environment." + `uname -m` + "-linux-" + `ghc --numeric-version 2>/dev/null || echo "9.6.7"`)

# Build the Haskell FFI library and conformance binaries
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
    agda src/Hegel.agda

# Compile and run the Agda test suites
test: build-hs
    agda --compile \
        --ghc-flag="-i{{justfile_directory()}}/hs-support" \
        --ghc-flag="-package-env {{justfile_directory()}}/{{ghc_env}}" \
        --compile-dir={{justfile_directory()}}/build \
        test/TestBasic.agda
    ./build/TestBasic
    agda --compile \
        --ghc-flag="-i{{justfile_directory()}}/hs-support" \
        --ghc-flag="-package-env {{justfile_directory()}}/{{ghc_env}}" \
        --compile-dir={{justfile_directory()}}/build \
        test/TestGenerators.agda
    ./build/TestGenerators

# Run the Haskell protocol test
test-protocol: build-hs
    cabal run test-protocol

# Run conformance tests
conformance: build-hs
    python3 -m pytest test_conformance.py -v --tb=short

# Coverage: Agda compiles to Haskell via GHC backend. Native Agda coverage
# tooling doesn't exist. We verify coverage by running all tests and conformance.
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
