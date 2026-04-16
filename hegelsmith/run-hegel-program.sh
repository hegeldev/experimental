#!/usr/bin/env bash
set -euo pipefail

# Script for use with hegelsmith: receives a hegel-rust program on stdin,
# compiles and runs it, and checks that any panics are legitimate
# "property test failed" messages, not invalid-argument or internal errors.
#
# Exit 0: program ran fine (passed or failed with a proper property-test message)
# Exit 1: program failed in a way that indicates a bug
#
# Compiles the program as a --example in the current cargo project,
# which must have hegeltest as a dependency.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SCRIPT_DIR/examples"
cat > "$SCRIPT_DIR/examples/hegelsmith_test.rs"

if ! cargo build --manifest-path "$SCRIPT_DIR/Cargo.toml" --example hegelsmith_test --quiet 2>"$SCRIPT_DIR/compile_err.txt"; then
    echo "COMPILATION FAILED:" >&2
    cat "$SCRIPT_DIR/compile_err.txt" >&2
    echo "---" >&2
    echo "Source:" >&2
    cat "$SCRIPT_DIR/examples/hegelsmith_test.rs" >&2
    exit 1
fi

BINARY="$SCRIPT_DIR/target/debug/examples/hegelsmith_test"
set +e
"$BINARY" >"$SCRIPT_DIR/stdout.txt" 2>"$SCRIPT_DIR/stderr.txt"
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
    exit 0
fi

STDERR=$(cat "$SCRIPT_DIR/stderr.txt")

BAD_PATTERNS=(
    "Cannot have max_value < min_value"
    "Cannot have max_size < min_size"
    "Cannot have allow_nan=true"
    "Cannot have allow_infinity=true"
    "cannot be empty"
    "one_of requires at least one"
    "Failed to deserialize value"
    "Expected array, got"
    "Expected text response"
    "Expected bool from"
    "Failed to communicate with Hegel"
    "Bad handshake response"
    "hegel-rust supports protocol versions"
    "hegel server process exited unexpectedly"
    "Failed to spawn hegel"
    "Timeout waiting for hegel"
)

for pattern in "${BAD_PATTERNS[@]}"; do
    if echo "$STDERR" | grep -qF "$pattern"; then
        echo "BAD FAILURE (matched: $pattern):" >&2
        echo "$STDERR" >&2
        exit 1
    fi
done

GOOD_PATTERNS=(
    "Property test failed"
    "Health check failure"
    "Flaky test detected"
)

for pattern in "${GOOD_PATTERNS[@]}"; do
    if echo "$STDERR" | grep -qF "$pattern"; then
        exit 0
    fi
done

echo "UNEXPECTED FAILURE (exit code $EXIT_CODE):" >&2
echo "$STDERR" >&2
exit 1
