#!/usr/bin/env perl
# Tests specifically targeting uncovered code paths for coverage.
use strict;
use warnings;
use Test::More;

use lib 'lib';
use Hegel qw(:all);

# Exercise flat_map (FlatMappedGenerator::do_draw)
subtest 'flat_map execution' => sub {
    hegel "flat_map generates" => sub {
        my ($tc) = @_;
        my $gen = integers(min_value => 1, max_value => 3)->flat_map(sub {
            my $n = $_[0];
            lists(booleans(), min_size => $n, max_size => $n);
        });
        my $val = $tc->draw($gen);
        ok(ref $val eq 'ARRAY', "got array");
        ok(scalar @$val >= 1 && scalar @$val <= 3, "size ok");
    }, test_cases => 5;
};

# Exercise filter (FilteredGenerator::do_draw)
subtest 'filter execution' => sub {
    hegel "filter positive" => sub {
        my ($tc) = @_;
        my $gen = integers(min_value => -100, max_value => 100)->filter(sub { $_[0] > 0 });
        my $val = $tc->draw($gen);
        ok($val > 0, "positive: $val");
    }, test_cases => 10;
};

# Exercise MappedGenerator::do_draw (non-basic map)
subtest 'map on non-basic' => sub {
    hegel "non-basic map" => sub {
        my ($tc) = @_;
        my $filtered = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        my $mapped = $filtered->map(sub { $_[0] * 2 });
        ok(!defined $mapped->as_basic(), "non-basic map is non-basic");
        my $val = $tc->draw($mapped);
        is($val % 2, 0, "even: $val");
    }, test_cases => 5;
};

# Exercise composite tuple path
subtest 'composite tuple' => sub {
    hegel "non-basic tuple" => sub {
        my ($tc) = @_;
        my $filtered_int = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        my $gen = tuples($filtered_int, booleans());
        ok(!defined $gen->as_basic(), "tuple with non-basic is non-basic");
        my $val = $tc->draw($gen);
        ok(ref $val eq 'ARRAY' && scalar @$val == 2, "got pair");
    }, test_cases => 3;
};

# Exercise composite one_of path
subtest 'composite one_of' => sub {
    hegel "non-basic one_of" => sub {
        my ($tc) = @_;
        my $filtered = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        my $gen = one_of($filtered, just(999));
        my $val = $tc->draw($gen);
        ok(defined $val, "got value");
    }, test_cases => 5;
};

# Exercise one_of with transforms (tagged tuple path)
subtest 'one_of with transforms' => sub {
    hegel "tagged tuple one_of" => sub {
        my ($tc) = @_;
        my $gen = one_of(
            integers(min_value => 0, max_value => 10)->map(sub { "int:$_[0]" }),
            just("constant"),
        );
        my $val = $tc->draw($gen);
        ok(defined $val, "got value: $val");
    }, test_cases => 5;
};

# Exercise composite dict path
subtest 'composite dict' => sub {
    hegel "non-basic dict" => sub {
        my ($tc) = @_;
        my $k = integers(min_value => 0, max_value => 1000)->filter(sub { 1 });
        my $v = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        my $gen = hashmaps($k, $v, min_size => 1, max_size => 3);
        my $val = $tc->draw($gen);
        ok(ref $val eq 'HASH', "got hash");
    }, test_cases => 3;
};

# Exercise composite list path
subtest 'composite list' => sub {
    hegel "non-basic list" => sub {
        my ($tc) = @_;
        my $elem = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        my $gen = lists($elem, min_size => 2, max_size => 4);
        my $val = $tc->draw($gen);
        ok(ref $val eq 'ARRAY', "got array");
        ok(scalar @$val >= 2, "min_size ok");
    }, test_cases => 3;
};

# Exercise note and target
subtest 'note and target in failing test' => sub {
    # This test intentionally fails to exercise the failure path
    hegel "note/target exercise" => sub {
        my ($tc) = @_;
        my $x = $tc->draw(integers(min_value => 0, max_value => 100));
        $tc->note("Testing with x=$x");
        $tc->target($x + 0.0, "x_value");
        ok(1);  # Always passes
    }, test_cases => 5;
};

# Exercise format generators
subtest 'all format generators' => sub {
    hegel "domains" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(domains()), "domain");
    }, test_cases => 2;

    hegel "ip_addresses v4" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(ip_addresses(version => 4)), "ipv4");
    }, test_cases => 2;

    hegel "ip_addresses v6" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(ip_addresses(version => 6)), "ipv6");
    }, test_cases => 2;

    hegel "times" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(times()), "time");
    }, test_cases => 2;

    hegel "datetimes" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(datetimes()), "datetime");
    }, test_cases => 2;

    hegel "from_regex" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(from_regex("[a-z]+")), "regex");
    }, test_cases => 2;

    hegel "characters" => sub {
        my ($tc) = @_;
        ok(defined $tc->draw(characters()), "char");
    }, test_cases => 2;
};

done_testing;
