package Hegel::Connection;
use strict;
use warnings;

use Carp qw(croak);
use Hegel::Protocol qw(read_packet write_packet CLOSE_STREAM_MESSAGE_ID);
use Hegel::Stream;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        reader         => $args{reader},   # filehandle for reading
        writer         => $args{writer},   # filehandle for writing
        streams        => {},              # stream_id => Stream object
        next_stream_id => 1,               # client streams are odd (1, 3, 5, ...)
        running        => 1,
    }, $class;
    return $self;
}

# Create stream 0 (control stream)
sub control_stream {
    my ($self) = @_;
    return $self->_register_stream(0);
}

# Allocate a new client stream (odd-numbered)
sub new_stream {
    my ($self) = @_;
    my $id = ($self->{next_stream_id} << 1) | 1;
    $self->{next_stream_id}++;
    return $self->_register_stream($id);
}

# Register a server-created stream (even-numbered)
sub connect_stream {
    my ($self, $stream_id) = @_;
    return $self->_register_stream($stream_id);
}

sub _register_stream {
    my ($self, $stream_id) = @_;
    my $stream = Hegel::Stream->new(
        stream_id  => $stream_id,
        connection => $self,
    );
    $self->{streams}{$stream_id} = $stream;
    return $stream;
}

sub unregister_stream {
    my ($self, $stream_id) = @_;
    delete $self->{streams}{$stream_id};
}

# Send a packet (thread-safe via single writer - Perl is single-threaded so no lock needed)
sub send_packet {
    my ($self, $packet) = @_;
    croak "Connection is closed" unless $self->{running};
    write_packet($self->{writer}, $packet);
}

# Demand-driven reader: read packets until one for the target stream arrives.
# Packets for other streams are dispatched to their inboxes.
sub read_packet_for_stream {
    my ($self, $target_stream_id) = @_;

    while (1) {
        croak "Connection is closed" unless $self->{running};

        my $pkt = eval { read_packet($self->{reader}) };
        if ($@) {
            $self->{running} = 0;
            croak "Connection read failed: $@";
        }

        my $sid = $pkt->{stream_id};

        # Check for close-stream notification
        if ($pkt->{message_id} == CLOSE_STREAM_MESSAGE_ID) {
            if (exists $self->{streams}{$sid}) {
                $self->{streams}{$sid}->mark_closed();
            }
            next;
        }

        # If it's for the target stream, return it directly
        if ($sid == $target_stream_id) {
            return $pkt;
        }

        # Otherwise, dispatch to the appropriate stream's inbox
        if (exists $self->{streams}{$sid}) {
            $self->{streams}{$sid}->push_inbox($pkt);
        }
        # Packets for unknown streams are silently dropped
    }
}

# Shutdown the connection
sub close {
    my ($self) = @_;
    $self->{running} = 0;
    eval { CORE::close($self->{writer}) };
    eval { CORE::close($self->{reader}) };
}

1;
