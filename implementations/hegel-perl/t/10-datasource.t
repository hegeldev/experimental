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

# --- Exercise print_draws with undef ---
subtest 'print_draws with undef value' => sub {
    my $ds = FakeDataSource->new(generate_values => [undef]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);
    my $gen = Hegel::BasicGenerator->new(schema => { type => 'integer' });
    $tc->draw($gen);

    my $output = '';
    { local *STDERR; open STDERR, '>', \$output; $tc->print_draws(); }
    like($output, qr/undef/, "undef value printed");
};

# --- Exercise print_draws with nested hash/array ---
subtest 'print_draws with nested structures' => sub {
    my $ds = FakeDataSource->new(generate_values => [{a => [1, undef]}]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);
    my $gen = Hegel::BasicGenerator->new(schema => { type => 'dict' });
    $tc->draw($gen);

    my $output = '';
    { local *STDERR; open STDERR, '>', \$output; $tc->print_draws(); }
    like($output, qr/a =>/, "nested hash printed");
};

# --- Exercise print_notes when not final (no output) ---
subtest 'print_notes not final' => sub {
    my $ds = FakeDataSource->new();
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 0);
    $tc->note("should not print");
    my $output = '';
    { local *STDERR; open STDERR, '>', \$output; $tc->print_notes(); }
    is($output, '', "no output when not final");
};

# --- Exercise print_draws when not final (no output) ---
subtest 'print_draws not final' => sub {
    my $ds = FakeDataSource->new(generate_values => [42]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 0);
    my $gen = Hegel::BasicGenerator->new(schema => { type => 'integer' });
    $tc->draw($gen);
    my $output = '';
    { local *STDERR; open STDERR, '>', \$output; $tc->print_draws(); }
    is($output, '', "no output when not final");
};

# --- Exercise draw recording at span_depth > 0 (no recording) ---
subtest 'draw at span_depth > 0 not recorded' => sub {
    my $ds = FakeDataSource->new(generate_values => [1, 2]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);
    $tc->start_span(1);  # depth = 1
    my $gen = Hegel::BasicGenerator->new(schema => { type => 'integer' });
    $tc->draw($gen);  # not recorded (depth > 0)
    $tc->stop_span(0);
    # Only draws at depth=0 are recorded
    my $output = '';
    { local *STDERR; open STDERR, '>', \$output; $tc->print_draws(); }
    is($output, '', "no draws recorded at depth > 0");
};

# --- Exercise ServerDataSource _check_error: UnsatisfiedAssumption ---
subtest 'ServerDataSource UnsatisfiedAssumption error' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub {
        return { error => "test", type => "UnsatisfiedAssumption" };
    };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->generate({ type => 'integer' }) }
        qr/Hegel::UnsatisfiedAssumption/, "UnsatisfiedAssumption propagated";
};

# --- Exercise ServerDataSource _check_error: generic error ---
subtest 'ServerDataSource generic error' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub {
        return { error => "something bad", type => "InvalidArgument" };
    };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->generate({ type => 'integer' }) }
        qr/Hegel::UnsatisfiedAssumption/, "generic error becomes UnsatisfiedAssumption";
};

# --- Exercise ServerDataSource _handle_error with StopTest exception ---
subtest 'ServerDataSource _handle_error with StopTest' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub { die Hegel::StopTest->new("from stream") };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->generate({ type => 'integer' }) }
        qr/Hegel::StopTest/, "StopTest re-thrown by _handle_error";
};

# --- Exercise ServerDataSource _handle_error with UnsatisfiedAssumption ---
subtest 'ServerDataSource _handle_error with UnsatisfiedAssumption' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub { die Hegel::UnsatisfiedAssumption->new() };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->generate({ type => 'integer' }) }
        qr/Hegel::UnsatisfiedAssumption/, "UnsatisfiedAssumption re-thrown";
};

# --- Exercise ServerDataSource _handle_error in start_span ---
subtest 'ServerDataSource _handle_error in start_span' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub { die "connection broken" };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->start_span(1) } qr/Hegel::StopTest/, "connection error in start_span";
};

# --- Exercise ServerDataSource _handle_error in new_collection ---
subtest 'ServerDataSource _handle_error in new_collection' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub { die "broken" };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->new_collection(1, 5) } qr/Hegel::StopTest/, "error in new_collection";
};

# --- Exercise ServerDataSource _handle_error in collection_more ---
subtest 'ServerDataSource _handle_error in collection_more' => sub {
    use Hegel::DataSource;
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub { die "broken" };
    local *Hegel::Stream::close_stream = sub { };
    my $mock_stream = bless { closed => 0 }, 'Hegel::Stream';
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->collection_more(0) } qr/Hegel::StopTest/, "error in collection_more";
};

# --- Exercise ServerDataSource stop_span when aborted ---
subtest 'ServerDataSource stop_span when aborted' => sub {
    use Hegel::DataSource;
    my $ds = bless { stream => undef, aborted => 1 }, 'Hegel::ServerDataSource';
    # stop_span should be a no-op when aborted
    $ds->stop_span(0);
    pass("stop_span silently returns when aborted");
};

# --- Exercise ServerDataSource mark_complete when aborted ---
subtest 'ServerDataSource mark_complete when aborted' => sub {
    use Hegel::DataSource;
    my $ds = bless { stream => undef, aborted => 1 }, 'Hegel::ServerDataSource';
    $ds->mark_complete("VALID", "TEST");
    pass("mark_complete silently returns when aborted");
};

# --- Exercise ServerDataSource collection_reject when aborted ---
subtest 'ServerDataSource collection_reject when aborted' => sub {
    use Hegel::DataSource;
    my $ds = bless { stream => undef, aborted => 1 }, 'Hegel::ServerDataSource';
    $ds->collection_reject(0, "test");
    pass("collection_reject silently returns when aborted");
};

# --- StopTest message accessor ---
subtest 'StopTest message accessor' => sub {
    my $err = Hegel::StopTest->new("test message");
    is($err->message, "test message", "message accessor works");
};

# --- _dump_value for non-ref scalars ---
subtest 'dump_value plain scalar' => sub {
    my $ds = FakeDataSource->new(generate_values => ["hello"]);
    my $tc = Hegel::TestCase->new(data_source => $ds, is_final => 1);
    my $gen = Hegel::BasicGenerator->new(schema => { type => 'string' });
    $tc->draw($gen);
    my $output = '';
    { local *STDERR; open STDERR, '>', \$output; $tc->print_draws(); }
    like($output, qr/hello/, "plain string printed");
};

# --- Exercise assume with true condition (no-op) ---
subtest 'assume true is no-op' => sub {
    my $ds = FakeDataSource->new();
    my $tc = Hegel::TestCase->new(data_source => $ds);
    $tc->assume(1);  # should not throw
    pass("assume(true) is no-op");
};

done_testing;
