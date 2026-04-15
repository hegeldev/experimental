#!/usr/bin/env perl
# Tests for the last uncovered anonymous closures.
use strict;
use warnings;
use Test::More;

use lib 'lib';
use Hegel qw(:all);

# Exercise chained map on basic generator (Generator.pm:81)
# Need a basic generator with a transform, then map again
subtest 'chained map on basic with existing transform' => sub {
    hegel "double chain" => sub {
        my ($tc) = @_;
        # sampled_from has a transform (index -> value)
        my $gen = sampled_from([10, 20, 30]);
        # map again to chain transforms
        my $doubled = $gen->map(sub { $_[0] * 2 });
        ok(defined $doubled->as_basic(), "still basic after chained map");
        my $val = $tc->draw($doubled);
        ok(grep { $val == $_ } (20, 40, 60), "valid doubled sampled: $val");
    }, test_cases => 10;
};

# Exercise one_of tagged tuple transform (Collections.pm:240)
# Need one_of where at least one branch has a transform
subtest 'one_of with transforms dispatches correctly' => sub {
    hegel "one_of tagged dispatch" => sub {
        my ($tc) = @_;
        my $gen = one_of(
            sampled_from([1, 2, 3]),  # has transform (index -> value)
            just(99),                  # has transform (null -> 99)
        );
        my $val = $tc->draw($gen);
        ok(grep { $val == $_ } (1, 2, 3, 99), "valid one_of result: $val");
    }, test_cases => 20;
};

# Exercise just() transform (Primitives.pm:74)
subtest 'just transform returns constant' => sub {
    hegel "just value" => sub {
        my ($tc) = @_;
        my $gen = just("hello");
        my $val = $tc->draw($gen);
        is($val, "hello", "got constant");
    }, test_cases => 3;
};

done_testing;
