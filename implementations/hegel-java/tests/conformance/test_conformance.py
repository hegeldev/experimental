"""
Conformance tests for hegel-java.

Each test class validates that our Java implementation correctly generates
values of the expected type and respects the requested constraints.
"""

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

BIN_DIR = Path(__file__).parent.parent.parent / "bin" / "conformance"

# Java long range
INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1

# Narrower range to avoid CBOR large integer encoding issues
INT32_MIN = -(2**31)
INT32_MAX = 2**31 - 1


def test_conformance(subtests):
    run_conformance_tests(
        [
            BooleanConformance(BIN_DIR / "test_booleans"),
            IntegerConformance(
                BIN_DIR / "test_integers",
                min_value=INT64_MIN,
                max_value=INT64_MAX,
            ),
            FloatConformance(BIN_DIR / "test_floats"),
            TextConformance(BIN_DIR / "test_text", no_surrogates=True),
            BinaryConformance(BIN_DIR / "test_binary"),
            ListConformance(
                BIN_DIR / "test_lists",
                min_value=INT32_MIN,
                max_value=INT32_MAX,
            ),
            SampledFromConformance(BIN_DIR / "test_sampled_from"),
            DictConformance(
                BIN_DIR / "test_maps",
                min_key=INT32_MIN,
                max_key=INT32_MAX,
                min_value=INT32_MIN,
                max_value=INT32_MAX,
            ),
            StopTestOnGenerateConformance(BIN_DIR / "test_error_handling"),
            StopTestOnMarkCompleteConformance(BIN_DIR / "test_error_handling"),
            StopTestOnCollectionMoreConformance(BIN_DIR / "test_error_handling"),
            StopTestOnNewCollectionConformance(BIN_DIR / "test_error_handling"),
            ErrorResponseConformance(BIN_DIR / "test_error_handling"),
            EmptyTestConformance(BIN_DIR / "test_error_handling"),
        ],
        subtests,
    )
