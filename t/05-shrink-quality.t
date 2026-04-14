#!/usr/bin/env perl
# Shrink quality tests: verify that Hegel produces minimal counterexamples.
use strict;
use warnings;
use Test::More;

use lib 'lib';
use Hegel qw(:all);
use Hegel::TestUtils qw(minimal);

subtest 'minimal integer is 0' => sub {
    my $val = minimal(integers(min_value => 0, max_value => 1000), sub { 1 });
    is($val, 0, "shrinks to 0");
};

subtest 'minimal integer satisfying condition' => sub {
    my $val = minimal(integers(min_value => 0, max_value => 1000), sub { $_[0] >= 5 });
    is($val, 5, "shrinks to smallest value >= 5");
};

subtest 'minimal list is empty or minimal' => sub {
    my $val = minimal(
        lists(integers(min_value => 0, max_value => 100), min_size => 0, max_size => 20),
        sub { scalar @{$_[0]} >= 1 },
    );
    is(scalar @$val, 1, "shrinks to 1 element");
    is($val->[0], 0, "element shrinks to 0");
};

subtest 'minimal list with sum constraint' => sub {
    my $val = minimal(
        lists(integers(min_value => 0, max_value => 100), min_size => 0, max_size => 20),
        sub {
            my $sum = 0;
            $sum += $_ for @{$_[0]};
            $sum >= 10;
        },
    );
    ok(scalar @$val <= 2, "minimal list for sum>=10 has few elements");
};

done_testing;
