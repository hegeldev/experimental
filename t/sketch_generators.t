#!/usr/bin/env perl
# API Sketch: Generator composition, combinators, collections

use strict;
use warnings;
use Test::More;
use Hegel qw(
    hegel integers floats text booleans binary
    lists hashmaps tuples one_of optional sampled_from just
    emails urls dates
);

# Lists of integers
hegel "list operations" => sub {
    my ($tc) = @_;
    my $xs = $tc->draw(lists(integers(), min_size => 1, max_size => 50));
    ok(ref $xs eq 'ARRAY', "got an array ref");
    ok(scalar @$xs >= 1 && scalar @$xs <= 50, "size in bounds");
};

# Hashmaps (dicts)
hegel "hashmap generation" => sub {
    my ($tc) = @_;
    my $map = $tc->draw(hashmaps(
        text(min_size => 1, max_size => 10),
        integers(min_value => 0, max_value => 999),
        min_size => 1, max_size => 5,
    ));
    ok(ref $map eq 'HASH', "got a hash ref");
};

# Tuples
hegel "tuple generation" => sub {
    my ($tc) = @_;
    my $pair = $tc->draw(tuples(text(), integers()));
    ok(ref $pair eq 'ARRAY' && scalar @$pair == 2, "got a pair");
};

# one_of for sum types
hegel "one_of generation" => sub {
    my ($tc) = @_;
    my $val = $tc->draw(one_of(integers(), text()));
    ok(defined $val, "got something");
};

# optional
hegel "optional generation" => sub {
    my ($tc) = @_;
    my $val = $tc->draw(optional(integers()));
    # $val is either an integer or undef
    ok(1, "optional value drawn");
};

# sampled_from
hegel "sampled_from" => sub {
    my ($tc) = @_;
    my $color = $tc->draw(sampled_from([qw(red green blue)]));
    ok(grep { $_ eq $color } qw(red green blue), "valid color");
};

# just (constant)
hegel "just returns constant" => sub {
    my ($tc) = @_;
    my $val = $tc->draw(just(42));
    is($val, 42, "always 42");
};

# map combinator
hegel "map preserves basicness" => sub {
    my ($tc) = @_;
    my $even = $tc->draw(integers(min_value => 0, max_value => 50)->map(sub { $_[0] * 2 }));
    is($even % 2, 0, "always even");
};

# filter combinator
hegel "filter positive" => sub {
    my ($tc) = @_;
    my $pos = $tc->draw(integers(min_value => -100, max_value => 100)->filter(sub { $_[0] > 0 }));
    ok($pos > 0, "positive");
};

# flat_map combinator
hegel "flat_map for dependent generation" => sub {
    my ($tc) = @_;
    my $list = $tc->draw(
        integers(min_value => 1, max_value => 5)->flat_map(sub {
            my ($n) = @_;
            lists(booleans(), min_size => $n, max_size => $n);
        })
    );
    ok(ref $list eq 'ARRAY', "got array");
    ok(scalar @$list >= 1 && scalar @$list <= 5, "right size");
};

# fixed_dictionaries for struct-like data
hegel "record generation" => sub {
    my ($tc) = @_;
    my $person = $tc->draw(fixed_dictionaries({
        name => text(min_size => 1, max_size => 50),
        age  => integers(min_value => 0, max_value => 120),
    }));
    ok($person->{name}, "has name");
    ok($person->{age} >= 0 && $person->{age} <= 120, "age in range");
};

# Format generators
hegel "format generators" => sub {
    my ($tc) = @_;
    my $email = $tc->draw(emails());
    like($email, qr/@/, "email has @");

    my $url = $tc->draw(urls());
    like($url, qr{://}, "url has ://");
};

done_testing;
