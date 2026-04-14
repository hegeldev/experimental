#!/usr/bin/env perl
# Tests for DataSource abstraction: base class, error paths, fake data source.
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel::DataSource;
use Hegel::TestCase;

# --- Base class abstract methods ---

subtest 'base DataSource methods are abstract' => sub {
    my $ds = bless {}, 'Hegel::DataSource';
    throws_ok { $ds->generate({}) } qr/generate not implemented/;
    throws_ok { $ds->start_span(1) } qr/start_span not implemented/;
    throws_ok { $ds->stop_span(0) } qr/stop_span not implemented/;
    throws_ok { $ds->new_collection(0, 10) } qr/new_collection not implemented/;
    throws_ok { $ds->collection_more(0) } qr/collection_more not implemented/;
    throws_ok { $ds->collection_reject(0) } qr/collection_reject not implemented/;
    throws_ok { $ds->target(1.0, "x") } qr/target not implemented/;
    throws_ok { $ds->mark_complete("VALID", "TEST") } qr/mark_complete not implemented/;
    ok(!$ds->test_aborted(), "base test_aborted returns false");
};

# --- FakeDataSource for testing error paths ---

package FakeDataSource;
use parent -norequire, 'Hegel::DataSource';

sub new {
    my ($class, %args) = @_;
    return bless {
        generate_values => $args{generate_values} || [0],
        generate_index  => 0,
        error_on        => $args{error_on} || '',
        aborted         => 0,
        spans           => 0,
        completed       => 0,
    }, $class;
}

sub test_aborted { $_[0]->{aborted} }

sub generate {
    my ($self, $schema) = @_;
    Carp::croak("FakeDataSource is aborted") if $self->{aborted};
    if ($self->{error_on} eq 'generate') {
        $self->{aborted} = 1;
        Hegel::StopTest->throw("fake StopTest on generate");
    }
    my $val = $self->{generate_values}[$self->{generate_index} % scalar @{$self->{generate_values}}];
    $self->{generate_index}++;
    return $val;
}

sub start_span {
    my ($self, $label) = @_;
    Carp::croak("FakeDataSource is aborted") if $self->{aborted};
    if ($self->{error_on} eq 'start_span') {
        $self->{aborted} = 1;
        Hegel::StopTest->throw("fake StopTest on start_span");
    }
    $self->{spans}++;
}

sub stop_span {
    my ($self, $discard) = @_;
    $self->{spans}-- if $self->{spans} > 0;
}

sub new_collection {
    my ($self, $min_size, $max_size) = @_;
    Carp::croak("FakeDataSource is aborted") if $self->{aborted};
    if ($self->{error_on} eq 'new_collection') {
        $self->{aborted} = 1;
        Hegel::StopTest->throw("fake StopTest on new_collection");
    }
    return 0;
}

sub collection_more {
    my ($self, $coll_id) = @_;
    return 0;  # always empty collection
}

sub collection_reject { }
sub target { }
sub mark_complete { $_[0]->{completed} = 1 }

package main;

# --- TestCase with FakeDataSource ---

subtest 'TestCase with fake data source - normal flow' => sub {
    my $ds = FakeDataSource->new(generate_values => [42, 99]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 0);

    my $gen = Hegel::BasicGenerator->new(
        schema => { type => 'integer' },
    );
    # BasicGenerator calls tc->generate which delegates to ds
    my $val = $tc->generate({ type => 'integer' });
    is($val, 42, "got value from fake");

    $val = $tc->generate({ type => 'integer' });
    is($val, 99, "got second value");

    ok(!$tc->is_aborted, "not aborted");
    ok(!$tc->is_final, "not final");
};

subtest 'TestCase with fake - StopTest on generate' => sub {
    my $ds = FakeDataSource->new(error_on => 'generate');
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 0);

    throws_ok { $tc->generate({ type => 'integer' }) }
        qr/Hegel::StopTest/, "StopTest propagates";
    ok($tc->is_aborted, "aborted after StopTest");
};

subtest 'TestCase with fake - StopTest on start_span' => sub {
    my $ds = FakeDataSource->new(error_on => 'start_span');
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 0);

    throws_ok { $tc->start_span(1) }
        qr/Hegel::StopTest/, "StopTest on start_span";
    ok($tc->is_aborted, "aborted");
};

subtest 'TestCase with fake - StopTest on new_collection' => sub {
    my $ds = FakeDataSource->new(error_on => 'new_collection');
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 0);

    throws_ok { $tc->new_collection(1, 5) }
        qr/Hegel::StopTest/, "StopTest on new_collection";
};

subtest 'TestCase note and print_notes' => sub {
    my $ds = FakeDataSource->new();
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);

    $tc->note("test note 1");
    $tc->note("test note 2");

    # Capture stderr
    my $output = '';
    {
        local *STDERR;
        open STDERR, '>', \$output;
        $tc->print_notes();
    }
    like($output, qr/test note 1/, "note 1 printed");
    like($output, qr/test note 2/, "note 2 printed");
};

subtest 'TestCase print_draws on final' => sub {
    my $ds = FakeDataSource->new(generate_values => [42]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);

    # Simulate a draw at span_depth=0
    use Hegel::Generator;
    my $gen = Hegel::BasicGenerator->new(schema => { type => 'integer' });
    my $val = $tc->draw($gen);

    my $output = '';
    {
        local *STDERR;
        open STDERR, '>', \$output;
        $tc->print_draws();
    }
    like($output, qr/draw = 42/, "draw value printed");
};

subtest 'TestCase print_draws with complex values' => sub {
    my $ds = FakeDataSource->new(generate_values => [[1, 2, 3]]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);

    my $gen = Hegel::BasicGenerator->new(schema => { type => 'list' });
    my $val = $tc->draw($gen);

    my $output = '';
    {
        local *STDERR;
        open STDERR, '>', \$output;
        $tc->print_draws();
    }
    like($output, qr/\[1, 2, 3\]/, "array printed");
};

subtest 'TestCase print_draws with hash' => sub {
    my $ds = FakeDataSource->new(generate_values => [{a => 1}]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);

    my $gen = Hegel::BasicGenerator->new(schema => { type => 'dict' });
    my $val = $tc->draw($gen);

    my $output = '';
    {
        local *STDERR;
        open STDERR, '>', \$output;
        $tc->print_draws();
    }
    like($output, qr/a => 1/, "hash printed");
};

done_testing;
