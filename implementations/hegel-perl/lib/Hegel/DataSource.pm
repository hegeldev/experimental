package Hegel::DataSource;
use strict;
use warnings;

# Abstract interface for data sources. TestCase calls these methods
# instead of protocol stream methods directly. This allows faking
# for test coverage without a live server.

sub generate       { die ref($_[0]) . "::generate not implemented" }
sub start_span     { die ref($_[0]) . "::start_span not implemented" }
sub stop_span      { die ref($_[0]) . "::stop_span not implemented" }
sub new_collection { die ref($_[0]) . "::new_collection not implemented" }
sub collection_more   { die ref($_[0]) . "::collection_more not implemented" }
sub collection_reject { die ref($_[0]) . "::collection_reject not implemented" }
sub target         { die ref($_[0]) . "::target not implemented" }
sub mark_complete  { die ref($_[0]) . "::mark_complete not implemented" }
sub test_aborted   { return 0 }

# --- ServerDataSource: wraps the real protocol stream ---

package Hegel::ServerDataSource;
use parent -norequire, 'Hegel::DataSource';
use Carp qw(croak);
use Types::Serialiser;
use Hegel::Protocol qw(cbor_encode cbor_decode);

sub new {
    my ($class, %args) = @_;
    return bless {
        stream  => $args{stream},
        aborted => 0,
    }, $class;
}

sub test_aborted { $_[0]->{aborted} }

sub generate {
    my ($self, $schema) = @_;
    croak "DataSource is aborted" if $self->{aborted};
    my $response = eval { $self->{stream}->request_cbor({ command => 'generate', schema => $schema }) };
    if ($@) { $self->_handle_error($@) }
    $self->_check_error($response);
    return $response;
}

sub start_span {
    my ($self, $label) = @_;
    croak "DataSource is aborted" if $self->{aborted};
    my $response = eval { $self->{stream}->request_cbor({ command => 'start_span', label => $label }) };
    if ($@) { $self->_handle_error($@) }
    $self->_check_error($response);
}

sub stop_span {
    my ($self, $discard) = @_;
    return if $self->{aborted};
    $discard //= 0;
    eval {
        $self->{stream}->request_cbor({
            command => 'stop_span',
            discard => $discard ? Types::Serialiser::true : Types::Serialiser::false,
        });
    };
}

sub new_collection {
    my ($self, $min_size, $max_size) = @_;
    croak "DataSource is aborted" if $self->{aborted};
    my $request = { command => 'new_collection', min_size => $min_size };
    $request->{max_size} = $max_size if defined $max_size;
    my $response = eval { $self->{stream}->request_cbor($request) };
    if ($@) { $self->_handle_error($@) }
    $self->_check_error($response);
    return "$response";
}

sub collection_more {
    my ($self, $collection_id) = @_;
    croak "DataSource is aborted" if $self->{aborted};
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
    my $response = eval { $self->{stream}->request_cbor($request) };
    if ($@) { $self->_handle_error($@) }
    $self->_check_error($response);
}

sub target {
    my ($self, $value, $label) = @_;
    croak "DataSource is aborted" if $self->{aborted};
    $self->{stream}->request_cbor({
        command => 'target',
        value   => $value + 0.0,
        label   => $label,
    });
}

sub mark_complete {
    my ($self, $status, $origin) = @_;
    return if $self->{aborted};
    eval {
        $self->{stream}->request_cbor({
            command => 'mark_complete',
            status  => $status,
            origin  => $origin,
        });
    };
    $self->{stream}->close_stream();
}

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
        Hegel::UnsatisfiedAssumption->throw();
    }
}

sub _handle_error {
    my ($self, $err) = @_;
    if (ref $err && $err->isa('Hegel::StopTest')) { die $err }
    if (ref $err && $err->isa('Hegel::UnsatisfiedAssumption')) { die $err }
    $self->{aborted} = 1;
    Hegel::StopTest->throw("Connection error: $err");
}

1;
