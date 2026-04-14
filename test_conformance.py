"""Conformance tests for hegel-agda."""
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


def find_exe(name):
    result = subprocess.run(
        ["cabal", "list-bin", name],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        return Path(result.stdout.strip())
    raise FileNotFoundError(f"Cannot find executable: {name}")


INT_MIN = -(2**63)
INT_MAX = 2**63 - 1


def test_conformance(subtests):
    error_handling_bin = find_exe("test_error_handling")

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
            StopTestOnGenerateConformance(error_handling_bin),
            StopTestOnMarkCompleteConformance(error_handling_bin),
            StopTestOnCollectionMoreConformance(error_handling_bin),
            StopTestOnNewCollectionConformance(error_handling_bin),
            ErrorResponseConformance(error_handling_bin),
            EmptyTestConformance(error_handling_bin),
        ],
        subtests,
    )
