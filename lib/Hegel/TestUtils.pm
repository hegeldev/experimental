package Hegel::TestUtils;
use strict;
use warnings;

use Hegel::Runner;
use Exporter 'import';
our @EXPORT_OK = qw(assert_all_examples find_any minimal assert_no_examples);

# Run a hegel test and check that all generated values satisfy the predicate.
sub assert_all_examples {
    my ($gen, $pred, %opts) = @_;
    my $test_cases = $opts{test_cases} || 100;
    my @failures;

    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $val = $tc->draw($gen);
            unless ($pred->($val)) {
                push @failures, $val;
                die "Predicate failed for value";
            }
        },
        settings => { test_cases => $test_cases },
    );

    eval { $runner->run() };

    if (@failures) {
        die "assert_all_examples: predicate failed for " . scalar(@failures) . " example(s)";
    }
}

# Find the first generated value satisfying the condition.
sub find_any {
    my ($gen, $cond, %opts) = @_;
    my $test_cases = $opts{test_cases} || 100;
    my $found;

    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $val = $tc->draw($gen);
            if ($cond->($val)) {
                $found = $val;
                die "Found matching value";  # Abort test to report as INTERESTING
            }
        },
        settings => { test_cases => $test_cases },
    );

    eval { $runner->run() };

    if (defined $found) {
        return $found;
    }
    die "find_any: no example satisfying condition found in $test_cases test cases";
}

# Find the minimal (most-shrunk) value satisfying the condition.
sub minimal {
    my ($gen, $cond, %opts) = @_;
    my $test_cases = $opts{test_cases} || 100;
    my $found;

    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $val = $tc->draw($gen);
            if ($cond->($val)) {
                $found = $val;
                die "Found matching value";
            }
        },
        settings => { test_cases => $test_cases },
    );

    eval { $runner->run() };

    if (defined $found) {
        return $found;  # The last value set by the final (shrunk) replay
    }
    die "minimal: no example satisfying condition found in $test_cases test cases";
}

# Assert that no generated values satisfy the condition.
sub assert_no_examples {
    my ($gen, $cond, %opts) = @_;
    my $test_cases = $opts{test_cases} || 100;

    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $val = $tc->draw($gen);
            if ($cond->($val)) {
                die "Found example satisfying condition";
            }
        },
        settings => { test_cases => $test_cases },
    );

    my $result = eval { $runner->run() };

    if ($result && !$result->{passed}) {
        die "assert_no_examples: found an example satisfying the condition";
    }
}

1;
