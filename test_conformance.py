"""Conformance tests for hegel-agda.

Run with: pytest test_conformance.py -v
"""
import subprocess
from pathlib import Path

from hegel.conformance import (
    BinaryConformance,
    BooleanConformance,
    DictConformance,
    EmptyTestConformance,
    ErrorResponseConformance,
    FloatConformance,
    IntegerConformance,
    ListConformance,
    SampledFromConformance,
    StopTestOnCollectionMoreConformance,
    StopTestOnGenerateConformance,
    StopTestOnMarkCompleteConformance,
    StopTestOnNewCollectionConformance,
    TextConformance,
    run_conformance_tests,
)

# Find the cabal build directory for executables
def find_exe(name):
    """Find a cabal-built executable."""
    result = subprocess.run(
        ["cabal", "list-bin", name],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        return Path(result.stdout.strip())
    # Fallback: search in dist-newstyle
    for p in Path("dist-newstyle").rglob(name):
        if p.is_file() and p.stat().st_mode & 0o111:
            return p
    raise FileNotFoundError(f"Cannot find executable: {name}")

# Agda integers use arbitrary precision, but for conformance we use Int64 range
INT_MIN = -(2**63)
INT_MAX = 2**63 - 1


def test_conformance(subtests):
    run_conformance_tests(
        [
            BooleanConformance(find_exe("test_booleans")),
            IntegerConformance(
                find_exe("test_integers"), min_value=INT_MIN, max_value=INT_MAX
            ),
            FloatConformance(find_exe("test_floats")),
            TextConformance(find_exe("test_text")),
            BinaryConformance(find_exe("test_binary")),
            ListConformance(
                find_exe("test_lists"), min_value=INT_MIN, max_value=INT_MAX
            ),
            SampledFromConformance(find_exe("test_sampled_from")),
            DictConformance(
                find_exe("test_dicts"),
                min_key=INT_MIN,
                max_key=INT_MAX,
                min_value=INT_MIN,
                max_value=INT_MAX,
            ),
        ],
        subtests,
        skip_tests={
            EmptyTestConformance,
            StopTestOnMarkCompleteConformance,
            ErrorResponseConformance,
            StopTestOnCollectionMoreConformance,
            StopTestOnNewCollectionConformance,
            StopTestOnGenerateConformance,
        },
    )
