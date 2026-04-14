# Hegel Java justfile

JAR := "target/hegel-java-0.1.0-SNAPSHOT-jar-with-dependencies.jar"

# Run tests with JaCoCo coverage enforcement
coverage:
    mvn verify -Dsurefire.failIfNoSpecifiedTests=false

# Run tests only (without coverage check)
test:
    mvn test -Dsurefire.failIfNoSpecifiedTests=false

# Build the fat jar and create conformance binary wrappers
build-conformance:
    #!/usr/bin/env bash
    set -euo pipefail
    mvn package -DskipTests -q assembly:single -q
    mkdir -p bin/conformance
    REPO_ROOT="$(pwd)"
    JAR="${REPO_ROOT}/{{JAR}}"
    declare -A BINARIES
    BINARIES=(
        [test_booleans]="dev.hegel.conformance.binaries.TestBooleans"
        [test_integers]="dev.hegel.conformance.binaries.TestIntegers"
        [test_floats]="dev.hegel.conformance.binaries.TestFloats"
        [test_text]="dev.hegel.conformance.binaries.TestText"
        [test_binary]="dev.hegel.conformance.binaries.TestBinary"
        [test_lists]="dev.hegel.conformance.binaries.TestLists"
        [test_sampled_from]="dev.hegel.conformance.binaries.TestSampledFrom"
        [test_maps]="dev.hegel.conformance.binaries.TestMaps"
        [test_error_handling]="dev.hegel.conformance.binaries.TestErrorHandling"
    )
    for name in "${!BINARIES[@]}"; do
        class="${BINARIES[$name]}"
        wrapper="${REPO_ROOT}/bin/conformance/${name}"
        printf '#!/usr/bin/env bash\nexec java -cp "%s" "%s" "$@"\n' \
            "${JAR}" "${class}" > "${wrapper}"
        chmod +x "${wrapper}"
    done
    echo "Built $(ls bin/conformance | wc -l) conformance binaries"

# Run conformance tests
conformance: build-conformance
    uv run --with 'hegel-core==0.4.0' --with pytest --with pytest-subtests --with hypothesis \
        pytest tests/conformance/ -v

# Format all Java source files with google-java-format
format:
    mvn com.spotify.fmt:fmt-maven-plugin:2.23:format -q

# Check that all Java source files are formatted (google-java-format)
lint:
    mvn com.spotify.fmt:fmt-maven-plugin:2.23:check

# Run all checks (format enforcement is part of mvn verify via fmt:check)
check: coverage
