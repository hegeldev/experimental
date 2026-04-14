import os
from pathlib import Path

# Ensure Perl can find its local modules
os.environ["PERL5LIB"] = os.path.expanduser("~/perl5/lib/perl5")

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

BIN_DIR = Path(__file__).parent.parent / "bin"

# Perl's native integers are 64-bit
INT_MIN = -(2**63)
INT_MAX = 2**63 - 1


def test_conformance(subtests):
    run_conformance_tests(
        [
            BooleanConformance(BIN_DIR / "test_booleans"),
            IntegerConformance(
                BIN_DIR / "test_integers", min_value=INT_MIN, max_value=INT_MAX
            ),
        ],
        subtests,
        skip_tests=[
            FloatConformance,
            TextConformance,
            BinaryConformance,
            ListConformance,
            SampledFromConformance,
            DictConformance,
            StopTestOnGenerateConformance,
            StopTestOnMarkCompleteConformance,
            ErrorResponseConformance,
            EmptyTestConformance,
            StopTestOnCollectionMoreConformance,
            StopTestOnNewCollectionConformance,
        ],
    )
