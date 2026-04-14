#!/usr/bin/env perl
# API Sketch: Basic property-based test
# This file shows the desired user experience. It will not compile yet.

use strict;
use warnings;
use Test::More;
use Hegel qw(hegel integers floats text booleans);

# Basic test: addition is commutative
hegel "addition is commutative" => sub {
    my ($tc) = @_;
    my $x = $tc->draw(integers());
    my $y = $tc->draw(integers());
    is($x + $y, $y + $x, "x + y == y + x");
};

# Test with constrained generators (named arguments)
hegel "bounded integers" => sub {
    my ($tc) = @_;
    my $n = $tc->draw(integers(min_value => 0, max_value => 100));
    ok($n >= 0 && $n <= 100, "n is in range");
};

# Test with settings
hegel "more test cases" => sub {
    my ($tc) = @_;
    my $x = $tc->draw(integers(min_value => -1000, max_value => 1000));
    ok(defined $x);
}, test_cases => 500, seed => 42;

done_testing;
