set ignore-comments := true

# Run all unit tests
test:
    raco test tests/

# Measure code coverage (must be 100% - exits non-zero if not)
coverage:
    raco cover \
        protocol.rkt connection.rkt runner.rkt test-case.rkt session.rkt conformance.rkt \
        generators/core.rkt generators/numeric.rkt generators/strings.rkt \
        generators/misc.rkt generators/collections.rkt generators/format.rkt \
        tests/test-protocol.rkt \
        tests/test-connection.rkt \
        tests/test-runner.rkt \
        tests/test-generators.rkt \
        tests/test-session.rkt \
        tests/test-conformance-helpers.rkt \
        tests/test-integration.rkt
    @python3 coverage-check.py

# Run conformance tests
conformance:
    uv run \
        --with 'hegel-core==0.4.0' \
        --with pytest \
        --with pytest-subtests \
        pytest conformance/test_conformance.py -v

# Format (racket has no standard formatter; just check syntax)
format:
    raco expand main.rkt > /dev/null 2>&1 || true

# Lint: check that all files compile cleanly
lint:
    raco make main.rkt conformance.rkt tests/test-protocol.rkt \
        tests/test-connection.rkt tests/test-runner.rkt tests/test-generators.rkt \
        tests/test-session.rkt tests/test-conformance-helpers.rkt

# Run all checks
check: test lint conformance
