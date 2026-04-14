#!/usr/bin/env perl
# API Sketch: Control functions (assume, note, target)

use strict;
use warnings;
use Test::More;
use Hegel qw(hegel integers floats);

# Using assume() to reject test cases
hegel "division identity" => sub {
    my ($tc) = @_;
    my $n = $tc->draw(integers(min_value => -100, max_value => 100));
    my $d = $tc->draw(integers(min_value => -20, max_value => 20));
    $tc->assume($d != 0);  # skip when divisor is zero

    my $q = int($n / $d);
    my $r = $n % $d;
    is($q * $d + $r, $n, "quotient-remainder identity");
};

# Using note() for debugging
hegel "sorting preserves length" => sub {
    my ($tc) = @_;
    my $list = $tc->draw(lists(integers(min_value => 0, max_value => 1000)));
    $tc->note("Testing with list of length " . scalar(@$list));

    my @sorted = sort { $a <=> $b } @$list;
    is(scalar @sorted, scalar @$list, "sorted list has same length");
};

# Using target() to guide search
hegel "find large sum" => sub {
    my ($tc) = @_;
    my $list = $tc->draw(lists(integers(min_value => 0, max_value => 100),
                               min_size => 1, max_size => 20));
    my $sum = 0;
    $sum += $_ for @$list;
    $tc->target($sum, "list sum");
    ok($sum < 10000, "sum is bounded");
};

done_testing;
