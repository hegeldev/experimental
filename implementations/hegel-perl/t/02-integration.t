#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';
use Hegel qw(:all);

# --- Basic property tests ---

subtest 'integers in range' => sub {
    hegel "bounded integers" => sub {
        my ($tc) = @_;
        my $x = $tc->draw(integers(min_value => 0, max_value => 100));
        ok($x >= 0 && $x <= 100, "in range: $x");
    }, test_cases => 10;
};

subtest 'booleans' => sub {
    hegel "booleans generate" => sub {
        my ($tc) = @_;
        my $b = $tc->draw(booleans());
        ok(defined $b, "defined");
    }, test_cases => 5;
};

subtest 'text generation' => sub {
    hegel "bounded text" => sub {
        my ($tc) = @_;
        my $s = $tc->draw(text(min_size => 1, max_size => 5));
        ok(defined $s, "text defined");
    }, test_cases => 5;
};

# --- Combinators ---

subtest 'map preserves basicness' => sub {
    hegel "map doubles" => sub {
        my ($tc) = @_;
        my $even = $tc->draw(integers(min_value => 0, max_value => 50)->map(sub { $_[0] * 2 }));
        is($even % 2, 0, "always even: $even");
    }, test_cases => 10;
};

subtest 'sampled_from' => sub {
    hegel "sample from list" => sub {
        my ($tc) = @_;
        my $v = $tc->draw(sampled_from([qw(a b c)]));
        ok(grep { $_ eq $v } qw(a b c), "valid: $v");
    }, test_cases => 10;
};

subtest 'just constant' => sub {
    hegel "constant value" => sub {
        my ($tc) = @_;
        is($tc->draw(just(42)), 42);
    }, test_cases => 3;
};

# --- Collections ---

subtest 'lists' => sub {
    hegel "bounded lists" => sub {
        my ($tc) = @_;
        my $xs = $tc->draw(lists(integers(min_value => 0, max_value => 100),
                                  min_size => 1, max_size => 5));
        ok(ref $xs eq 'ARRAY');
        ok(scalar @$xs >= 1 && scalar @$xs <= 5, "size: " . scalar @$xs);
    }, test_cases => 5;
};

subtest 'tuples' => sub {
    hegel "tuple generation" => sub {
        my ($tc) = @_;
        my $pair = $tc->draw(tuples(integers(), booleans()));
        ok(ref $pair eq 'ARRAY' && scalar @$pair == 2, "got pair");
    }, test_cases => 5;
};

subtest 'hashmaps basic' => sub {
    hegel "dict generation" => sub {
        my ($tc) = @_;
        my $d = $tc->draw(hashmaps(
            integers(min_value => 0, max_value => 1000),
            integers(min_value => 0, max_value => 100),
            min_size => 1, max_size => 3,
        ));
        ok(ref $d eq 'HASH', "got hash");
    }, test_cases => 3;
};

# --- Control functions ---

subtest 'assume rejects' => sub {
    hegel "assume filters" => sub {
        my ($tc) = @_;
        my $x = $tc->draw(integers(min_value => -10, max_value => 10));
        $tc->assume($x != 0);
        ok($x != 0, "not zero: $x");
    }, test_cases => 10;
};

# --- one_of ---

subtest 'one_of' => sub {
    hegel "one_of choice" => sub {
        my ($tc) = @_;
        my $v = $tc->draw(one_of(just(1), just(2), just(3)));
        ok($v >= 1 && $v <= 3, "valid choice: $v");
    }, test_cases => 10;
};

subtest 'optional' => sub {
    hegel "optional value" => sub {
        my ($tc) = @_;
        my $v = $tc->draw(optional(integers(min_value => 1, max_value => 100)));
        ok(!defined($v) || ($v >= 1 && $v <= 100), "valid optional");
    }, test_cases => 10;
};

done_testing;
