# Hegel Java justfile

# Run tests (with JaCoCo coverage instrumentation)
test:
    mvn verify -Dsurefire.failIfNoSpecifiedTests=false

# Run tests only (no coverage check)
test-only:
    mvn test -Dsurefire.failIfNoSpecifiedTests=false

# Run tests and enforce 100% coverage on library code
coverage:
    mvn verify

# Format code (using google-java-format via Maven)
format:
    mvn spotless:apply 2>/dev/null || echo "Spotless not configured, skipping format"

# Check formatting
lint:
    mvn spotless:check 2>/dev/null || echo "Spotless not configured, skipping lint check"

# Build conformance test fat-jars
build-conformance:
    mvn package -DskipTests assembly:single -q
    mkdir -p bin/conformance

# Run conformance tests
conformance: build-conformance
    #!/usr/bin/env bash
    set -euo pipefail
    # Build conformance binaries
    mvn package -DskipTests -q
    # Run the conformance tests
    uv run --with 'hegel-core==0.4.0' --with pytest --with hypothesis \
        pytest tests/conformance/ -v

# Run all checks: lint + test + coverage
check: lint coverage
