#!/usr/bin/env perl
# Tests for previously uncovered code paths.
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel qw(:all);
use Hegel::TestUtils qw(find_any assert_no_examples);

# Exercise find_any
subtest 'find_any finds a value' => sub {
    my $val = find_any(
        integers(min_value => 0, max_value => 100),
        sub { $_[0] > 50 },
        test_cases => 100,
    );
    ok($val > 50, "found value > 50: $val");
};

# Exercise assert_no_examples
subtest 'assert_no_examples succeeds' => sub {
    assert_no_examples(
        integers(min_value => 0, max_value => 10),
        sub { $_[0] > 100 },  # impossible
        test_cases => 50,
    );
    pass("no examples > 100 found");
};

# Exercise lists with element transform (anonymous closure in Collections)
subtest 'list with mapped elements' => sub {
    hegel "list with transform" => sub {
        my ($tc) = @_;
        my $gen = lists(
            integers(min_value => 0, max_value => 10)->map(sub { $_[0] * 10 }),
            min_size => 1, max_size => 3,
        );
        my $val = $tc->draw($gen);
        ok(ref $val eq 'ARRAY', "got array");
        for my $v (@$val) {
            is($v % 10, 0, "element divisible by 10: $v");
        }
    }, test_cases => 5;
};

# Exercise tuples with element transforms
subtest 'tuple with transforms' => sub {
    hegel "tuple with transform" => sub {
        my ($tc) = @_;
        my $gen = tuples(
            integers(min_value => 0, max_value => 5)->map(sub { "n=$_[0]" }),
            booleans(),
        );
        my $val = $tc->draw($gen);
        ok(ref $val eq 'ARRAY' && @$val == 2, "got pair");
        like($val->[0], qr/^n=\d+$/, "first is formatted: $val->[0]");
    }, test_cases => 5;
};

# Exercise dict with key/value transforms (basic path)
subtest 'dict with transforms' => sub {
    hegel "dict with transform" => sub {
        my ($tc) = @_;
        my $gen = hashmaps(
            integers(min_value => 0, max_value => 100)->map(sub { "key_$_[0]" }),
            integers(min_value => 0, max_value => 100)->map(sub { $_[0] * 2 }),
            min_size => 1, max_size => 3,
        );
        my $val = $tc->draw($gen);
        ok(ref $val eq 'HASH', "got hash");
        for my $k (keys %$val) {
            like($k, qr/^key_\d+$/, "key formatted: $k");
            is($val->{$k} % 2, 0, "value even: $val->{$k}");
        }
    }, test_cases => 3;
};

# Exercise one_of with transforms (tagged tuple path)
subtest 'one_of with mapped branches' => sub {
    hegel "one_of tagged" => sub {
        my ($tc) = @_;
        my $gen = one_of(
            integers(min_value => 0, max_value => 10)->map(sub { "int:$_[0]" }),
            just("constant")->map(sub { "const:$_[0]" }),
        );
        my $val = $tc->draw($gen);
        ok($val =~ /^(int:|const:)/, "got tagged value: $val");
    }, test_cases => 10;
};

# Exercise collection_reject (through dict with duplicate keys in non-basic mode)
subtest 'collection_reject via dict' => sub {
    hegel "non-basic dict exercises reject" => sub {
        my ($tc) = @_;
        # Use small key range to force duplicates and collection_reject
        my $key_gen = integers(min_value => 0, max_value => 3)->filter(sub { 1 });
        my $val_gen = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        my $gen = hashmaps($key_gen, $val_gen, min_size => 1, max_size => 3);
        my $val = $tc->draw($gen);
        ok(ref $val eq 'HASH', "got hash");
    }, test_cases => 5;
};

# Exercise is_final and is_aborted accessors
subtest 'TestCase accessors' => sub {
    hegel "accessor test" => sub {
        my ($tc) = @_;
        ok(!$tc->is_final, "not final during normal run");
        ok(!$tc->is_aborted, "not aborted during normal run");
        ok(1);
    }, test_cases => 1;
};

# Exercise from_regex (Primitives anonymous closure)
subtest 'from_regex with alphabet' => sub {
    hegel "regex with alphabet" => sub {
        my ($tc) = @_;
        my $gen = from_regex("[a-z]+", fullmatch => 1);
        my $val = $tc->draw($gen);
        ok(defined $val, "got regex match: $val");
    }, test_cases => 3;
};

done_testing;
