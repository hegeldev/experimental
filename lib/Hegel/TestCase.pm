package Hegel::TestCase;
use strict;
use warnings;

use Carp qw(croak);
use Hegel::Protocol qw(cbor_encode cbor_decode);

# Exception class for assume() failures
package Hegel::UnsatisfiedAssumption {
    sub new { bless {}, $_[0] }
    sub throw { die $_[0]->new() }
}

# Exception class for StopTest from server
package Hegel::StopTest {
    sub new { bless { message => $_[1] || 'StopTest' }, $_[0] }
    sub throw { die $_[0]->new($_[1]) }
    sub message { $_[0]->{message} }
}

package Hegel::TestCase;

# Span labels
use constant {
    LABEL_LIST         => 1,
    LABEL_LIST_ELEMENT => 2,
    LABEL_SET          => 3,
    LABEL_SET_ELEMENT  => 4,
    LABEL_MAP          => 5,
    LABEL_MAP_ENTRY    => 6,
    LABEL_TUPLE        => 7,
    LABEL_ONE_OF       => 8,
    LABEL_OPTIONAL     => 9,
    LABEL_FIXED_DICT   => 10,
    LABEL_FLAT_MAP     => 11,
    LABEL_FILTER       => 12,
    LABEL_MAPPED       => 13,
    LABEL_SAMPLED_FROM => 14,
    LABEL_ENUM_VARIANT => 15,
};

sub new {
    my ($class, %args) = @_;
    return bless {
        stream      => $args{stream},
        is_final    => $args{is_final} || 0,
        aborted     => 0,
        span_depth  => 0,
        notes       => [],
        draws       => [],
    }, $class;
}

sub is_final    { $_[0]->{is_final} }
sub is_aborted  { $_[0]->{aborted} }

# Draw a value from a generator
sub draw {
    my ($self, $generator, $label) = @_;
    croak "TestCase is aborted" if $self->{aborted};

    my $value = $generator->do_draw($self);

    # Record draw at top level (span_depth == 0) for output
    if ($self->{span_depth} == 0 && $self->{is_final}) {
        $label //= 'draw';
        push @{$self->{draws}}, { label => $label, value => $value };
    }

    return $value;
}

# Reject the current test case
sub assume {
    my ($self, $condition) = @_;
    return if $condition;
    Hegel::UnsatisfiedAssumption->throw();
}

# Record a note (displayed on final run only)
sub note {
    my ($self, $message) = @_;
    push @{$self->{notes}}, $message;
}

# Guide the search engine
sub target {
    my ($self, $value, $label) = @_;
    croak "TestCase is aborted" if $self->{aborted};
    $label //= 'target';

    $self->{stream}->request_cbor({
        command => 'target',
        value   => $value + 0.0,  # force float
        label   => $label,
    });
}

# --- Protocol commands ---

# Generate a value from a schema
sub generate {
    my ($self, $schema) = @_;
    croak "TestCase is aborted" if $self->{aborted};

    my $response = eval {
        $self->{stream}->request_cbor({
            command => 'generate',
            schema  => $schema,
        });
    };
    if ($@) {
        $self->_handle_error($@);
    }
    $self->_check_error($response);
    return $response;
}

# Start a span for structured generation
sub start_span {
    my ($self, $label) = @_;
    croak "TestCase is aborted" if $self->{aborted};
    $self->{span_depth}++;

    my $response = eval {
        $self->{stream}->request_cbor({
            command => 'start_span',
            label   => $label,
        });
    };
    if ($@) {
        $self->_handle_error($@);
    }
    $self->_check_error($response);
}

# Stop a span
sub stop_span {
    my ($self, $discard) = @_;
    $self->{span_depth}-- if $self->{span_depth} > 0;
    return if $self->{aborted};  # Don't send after abort

    $discard //= 0;
    eval {
        $self->{stream}->request_cbor({
            command => 'stop_span',
            discard => $discard ? \1 : \0,
        });
    };
    # Ignore errors in stop_span during cleanup
}

# Mark the test case as complete
sub mark_complete {
    my ($self, $status, $origin) = @_;
    return if $self->{aborted};  # Never send after abort

    eval {
        $self->{stream}->request_cbor({
            command => 'mark_complete',
            status  => $status,
            origin  => $origin,
        });
    };
    $self->{stream}->close_stream();
}

# --- Collection protocol ---

sub new_collection {
    my ($self, $min_size, $max_size) = @_;
    croak "TestCase is aborted" if $self->{aborted};

    my $request = {
        command  => 'new_collection',
        min_size => $min_size,
    };
    $request->{max_size} = $max_size if defined $max_size;

    my $response = eval { $self->{stream}->request_cbor($request) };
    if ($@) { $self->_handle_error($@) }
    $self->_check_error($response);
    return "$response";  # collection ID as string
}

sub collection_more {
    my ($self, $collection_id) = @_;
    croak "TestCase is aborted" if $self->{aborted};

    my $response = eval {
        $self->{stream}->request_cbor({
            command       => 'collection_more',
            collection_id => $collection_id + 0,
        });
    };
    if ($@) { $self->_handle_error($@) }
    $self->_check_error($response);
    return $response ? 1 : 0;
}

sub collection_reject {
    my ($self, $collection_id, $why) = @_;
    return if $self->{aborted};

    my $request = {
        command       => 'collection_reject',
        collection_id => $collection_id + 0,
    };
    $request->{why} = $why if defined $why;

    eval { $self->{stream}->request_cbor($request) };
}

# --- Error handling ---

sub _check_error {
    my ($self, $response) = @_;
    return unless ref $response eq 'HASH';

    if (exists $response->{error}) {
        my $error_type = $response->{type} || '';
        if ($error_type eq 'UnsatisfiedAssumption') {
            Hegel::UnsatisfiedAssumption->throw();
        }
        if ($error_type eq 'StopTest' || $error_type eq 'overflow'
            || (ref $response->{error} eq '' && $response->{error} =~ /overflow|StopTest/)) {
            $self->{aborted} = 1;
            Hegel::StopTest->throw($response->{error});
        }
        # Generic error - treat as assumption failure
        Hegel::UnsatisfiedAssumption->throw();
    }
}

sub _handle_error {
    my ($self, $err) = @_;
    if (ref $err && $err->isa('Hegel::StopTest')) {
        die $err;  # Re-throw
    }
    if (ref $err && $err->isa('Hegel::UnsatisfiedAssumption')) {
        die $err;  # Re-throw
    }
    # Connection error during test - mark as aborted
    $self->{aborted} = 1;
    Hegel::StopTest->throw("Connection error: $err");
}

# Print notes (on final run)
sub print_notes {
    my ($self) = @_;
    return unless $self->{is_final} && @{$self->{notes}};
    for my $note (@{$self->{notes}}) {
        print STDERR "Note: $note\n";
    }
}

# Print draws (on final run)
sub print_draws {
    my ($self) = @_;
    return unless $self->{is_final} && @{$self->{draws}};
    for my $draw (@{$self->{draws}}) {
        my $val = $draw->{value};
        my $str = ref $val ? _dump_value($val) : (defined $val ? "$val" : 'undef');
        print STDERR "  $draw->{label} = $str\n";
    }
}

sub _dump_value {
    my ($val) = @_;
    if (ref $val eq 'ARRAY') {
        return '[' . join(', ', map { ref $_ ? _dump_value($_) : (defined $_ ? $_ : 'undef') } @$val) . ']';
    }
    if (ref $val eq 'HASH') {
        return '{' . join(', ', map { "$_ => " . (defined $val->{$_} ? (ref $val->{$_} ? _dump_value($val->{$_}) : $val->{$_}) : 'undef') } sort keys %$val) . '}';
    }
    return "$val";
}

1;
