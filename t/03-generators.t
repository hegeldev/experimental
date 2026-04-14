#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel qw(:all);
use Hegel::TestUtils qw(assert_all_examples find_any assert_no_examples);

subtest 'integers respect bounds' => sub {
    assert_all_examples(
        integers(min_value => 10, max_value => 20),
        sub { $_[0] >= 10 && $_[0] <= 20 },
        test_cases => 50,
    );
    pass("all integers in bounds");
};

subtest 'floats respect bounds' => sub {
    assert_all_examples(
        floats(min_value => 0.0, max_value => 1.0, allow_nan => 0, allow_infinity => 0),
        sub { $_[0] >= 0.0 && $_[0] <= 1.0 },
        test_cases => 50,
    );
    pass("all floats in bounds");
};

subtest 'text respects size bounds' => sub {
    use Encode qw(decode);
    assert_all_examples(
        text(min_size => 2, max_size => 5),
        sub {
            my $s = eval { decode('UTF-8', $_[0]) } // $_[0];
            my $len = length($s);
            $len >= 2 && $len <= 5;
        },
        test_cases => 50,
    );
    pass("all text in bounds");
};

subtest 'binary respects size bounds' => sub {
    assert_all_examples(
        binary(min_size => 1, max_size => 10),
        sub { length($_[0]) >= 1 && length($_[0]) <= 10 },
        test_cases => 50,
    );
    pass("all binary in bounds");
};

subtest 'sampled_from returns valid values' => sub {
    my @options = (10, 20, 30);
    assert_all_examples(
        sampled_from(\@options),
        sub { grep { $_[0] == $_ } @options },
        test_cases => 50,
    );
    pass("all sampled values valid");
};

subtest 'map on basic preserves basicness' => sub {
    my $gen = integers(min_value => 0, max_value => 10)->map(sub { $_[0] * 3 });
    ok(defined $gen->as_basic(), "map on basic is still basic");
    assert_all_examples($gen, sub { $_[0] % 3 == 0 && $_[0] >= 0 && $_[0] <= 30 }, test_cases => 50);
    pass("mapped values correct");
};

subtest 'filter always non-basic' => sub {
    my $gen = integers(min_value => 0, max_value => 100)->filter(sub { $_[0] > 50 });
    ok(!defined $gen->as_basic(), "filter makes non-basic");
    assert_all_examples($gen, sub { $_[0] > 50 }, test_cases => 20);
    pass("filtered values correct");
};

subtest 'flat_map always non-basic' => sub {
    my $gen = integers(min_value => 1, max_value => 3)->flat_map(sub {
        my $n = $_[0];
        lists(booleans(), min_size => $n, max_size => $n);
    });
    ok(!defined $gen->as_basic(), "flat_map makes non-basic");
    pass("flat_map works");
};

subtest 'lists basic path' => sub {
    my $gen = lists(integers(min_value => 0, max_value => 100), min_size => 2, max_size => 5);
    ok(defined $gen->as_basic(), "list of basic is basic");
    assert_all_examples($gen, sub {
        ref $_[0] eq 'ARRAY' && scalar @{$_[0]} >= 2 && scalar @{$_[0]} <= 5
    }, test_cases => 30);
    pass("basic lists correct");
};

subtest 'lists non-basic path' => sub {
    my $elem = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
    my $gen = lists($elem, min_size => 1, max_size => 3);
    ok(!defined $gen->as_basic(), "list of non-basic is non-basic");
    pass("non-basic lists work");
};

subtest 'hashmaps basic path' => sub {
    my $gen = hashmaps(
        integers(min_value => 0, max_value => 1000),
        integers(min_value => 0, max_value => 100),
        min_size => 1, max_size => 3,
    );
    ok(defined $gen->as_basic(), "hashmap of basic is basic");
    pass("basic hashmaps work");
};

subtest 'tuples basic path' => sub {
    my $gen = tuples(integers(), booleans(), text(max_size => 5));
    ok(defined $gen->as_basic(), "tuple of basics is basic");
    pass("basic tuples work");
};

subtest 'one_of basic no transforms' => sub {
    my $gen = one_of(integers(min_value => 0, max_value => 10), integers(min_value => 90, max_value => 100));
    ok(defined $gen->as_basic(), "one_of of basics with no transforms is basic");
    pass("basic one_of works");
};

subtest 'optional' => sub {
    hegel "optional values" => sub {
        my ($tc) = @_;
        my $val = $tc->draw(optional(integers(min_value => 1, max_value => 100)));
        ok(!defined($val) || ($val >= 1 && $val <= 100), "valid optional");
    }, test_cases => 20;
};

subtest 'fixed_dictionaries' => sub {
    hegel "record generation" => sub {
        my ($tc) = @_;
        my $rec = $tc->draw(fixed_dictionaries({
            name => text(min_size => 1, max_size => 10),
            age  => integers(min_value => 0, max_value => 120),
        }));
        ok(ref $rec eq 'HASH', "got hash");
        ok(exists $rec->{name} && exists $rec->{age}, "has fields");
    }, test_cases => 10;
};

subtest 'assume rejects invalid cases' => sub {
    hegel "division by non-zero" => sub {
        my ($tc) = @_;
        my $d = $tc->draw(integers(min_value => -5, max_value => 5));
        $tc->assume($d != 0);
        ok($d != 0, "not zero: $d");
    }, test_cases => 20;
};

subtest 'note works' => sub {
    hegel "note test" => sub {
        my ($tc) = @_;
        my $x = $tc->draw(integers(min_value => 0, max_value => 100));
        $tc->note("x = $x");
        ok(1);
    }, test_cases => 3;
};

subtest 'target works' => sub {
    hegel "target test" => sub {
        my ($tc) = @_;
        my $x = $tc->draw(integers(min_value => 0, max_value => 100));
        $tc->target($x + 0.0, "value");
        ok(1);
    }, test_cases => 3;
};

subtest 'format generators' => sub {
    hegel "emails" => sub {
        my ($tc) = @_;
        my $e = $tc->draw(emails());
        ok(defined $e, "got email");
    }, test_cases => 3;

    hegel "urls" => sub {
        my ($tc) = @_;
        my $u = $tc->draw(urls());
        ok(defined $u, "got url");
    }, test_cases => 3;

    hegel "dates" => sub {
        my ($tc) = @_;
        my $d = $tc->draw(dates());
        ok(defined $d, "got date");
    }, test_cases => 3;
};

done_testing;
