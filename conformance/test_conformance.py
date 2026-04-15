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

CONFORMANCE_DIR = Path(__file__).parent

INT_MIN = -(2**31)
INT_MAX = 2**31 - 1


def test_conformance(subtests):
    run_conformance_tests(
        [
            BooleanConformance(CONFORMANCE_DIR / "test_booleans.rkt"),
            IntegerConformance(
                CONFORMANCE_DIR / "test_integers.rkt",
                min_value=INT_MIN,
                max_value=INT_MAX,
            ),
            FloatConformance(CONFORMANCE_DIR / "test_floats.rkt"),
            # no_surrogates=True: Racket strings are unicode but surrogate handling
            # in JSON round-trips can be lossy.
            TextConformance(
                CONFORMANCE_DIR / "test_text.rkt",
                no_surrogates=True,
            ),
            BinaryConformance(CONFORMANCE_DIR / "test_binary.rkt"),
            SampledFromConformance(CONFORMANCE_DIR / "test_sampled_from.rkt"),
            ListConformance(
                CONFORMANCE_DIR / "test_lists.rkt",
                min_value=INT_MIN,
                max_value=INT_MAX,
            ),
            DictConformance(
                CONFORMANCE_DIR / "test_hashmaps.rkt",
                min_key=INT_MIN,
                max_key=INT_MAX,
                min_value=INT_MIN,
                max_value=INT_MAX,
            ),
            StopTestOnGenerateConformance(
                CONFORMANCE_DIR / "test_error_handling.rkt"
            ),
            StopTestOnMarkCompleteConformance(
                CONFORMANCE_DIR / "test_error_handling.rkt"
            ),
            StopTestOnCollectionMoreConformance(
                CONFORMANCE_DIR / "test_error_handling.rkt"
            ),
            StopTestOnNewCollectionConformance(
                CONFORMANCE_DIR / "test_error_handling.rkt"
            ),
            ErrorResponseConformance(
                CONFORMANCE_DIR / "test_error_handling.rkt"
            ),
            EmptyTestConformance(CONFORMANCE_DIR / "test_error_handling.rkt"),
        ],
        subtests,
    )
