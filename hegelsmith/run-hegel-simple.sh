#!/usr/bin/env bash
set -euo pipefail

# Simple script: compile and run the hegel program, fail if it fails for any reason.
#
# Compiles the program as a --example in the current cargo project,
# which must have hegeltest as a dependency.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SCRIPT_DIR/examples"
cat > "$SCRIPT_DIR/examples/hegelsmith_test.rs"

if ! cargo build --manifest-path "$SCRIPT_DIR/Cargo.toml" --example hegelsmith_test --quiet 2>"$SCRIPT_DIR/compile_err.txt"; then
    echo "COMPILATION FAILED:" >&2
    cat "$SCRIPT_DIR/compile_err.txt" >&2
    exit 1
fi

exec "$SCRIPT_DIR/target/debug/examples/hegelsmith_test"
