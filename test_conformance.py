"""Conformance tests for hegel-agda.

These tests exercise the Agda generator library (not raw CBOR schemas).
Each conformance binary is an Agda program compiled via agda --compile
that uses the Hegel generator API (draw, integers, booleans, lists, etc.).
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

BUILD_DIR = Path(__file__).parent / "build"

INT_MIN = -(2**63)
INT_MAX = 2**63 - 1


def test_conformance(subtests):
    error_handling_bin = BUILD_DIR / "TestErrorHandling"

    run_conformance_tests(
        [
            BooleanConformance(BUILD_DIR / "TestBooleans"),
            IntegerConformance(
                BUILD_DIR / "TestIntegers", min_value=INT_MIN, max_value=INT_MAX
            ),
            FloatConformance(BUILD_DIR / "TestFloats"),
            TextConformance(BUILD_DIR / "TestText"),
            BinaryConformance(BUILD_DIR / "TestBinary"),
            ListConformance(
                BUILD_DIR / "TestLists", min_value=INT_MIN, max_value=INT_MAX
            ),
            SampledFromConformance(BUILD_DIR / "TestSampledFrom"),
            DictConformance(
                BUILD_DIR / "TestDicts",
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
