set ignore-comments := true

# Run all unit tests
test:
    raco test tests/

# Measure code coverage (must be 100% library coverage - exits non-zero if not)
# Note: raco cover runs all listed files including test files, so this also runs tests.
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

# Format: Racket has no standard code formatter.
# This target checks that all source files parse cleanly.
format:
    raco expand \
        protocol.rkt connection.rkt runner.rkt test-case.rkt session.rkt conformance.rkt \
        generators/core.rkt generators/numeric.rkt generators/strings.rkt \
        generators/misc.rkt generators/collections.rkt generators/format.rkt \
        main.rkt > /dev/null

# Lint: check that all files compile cleanly
lint:
    raco make main.rkt conformance.rkt \
        tests/test-protocol.rkt tests/test-connection.rkt tests/test-runner.rkt \
        tests/test-generators.rkt tests/test-session.rkt tests/test-conformance-helpers.rkt \
        conformance/test_booleans.rkt conformance/test_integers.rkt \
        conformance/test_floats.rkt conformance/test_text.rkt \
        conformance/test_binary.rkt conformance/test_sampled_from.rkt \
        conformance/test_lists.rkt conformance/test_hashmaps.rkt \
        conformance/test_error_handling.rkt

# Run all checks: coverage (includes tests) + lint + conformance
check: coverage lint conformance
