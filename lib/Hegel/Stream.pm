package Hegel::Stream;
use strict;
use warnings;

use Carp qw(croak);
use Hegel::Protocol qw(
    cbor_encode cbor_decode
    CLOSE_STREAM_MESSAGE_ID CLOSE_STREAM_PAYLOAD
);

sub new {
    my ($class, %args) = @_;
    return bless {
        stream_id      => $args{stream_id},
        connection     => $args{connection},
        next_message_id => $args{initial_message_id} || 0,
        inbox          => [],
        closed         => 0,
    }, $class;
}

sub stream_id { $_[0]->{stream_id} }
sub is_closed { $_[0]->{closed} }

sub mark_closed { $_[0]->{closed} = 1 }

# Push a packet into this stream's inbox (called by Connection dispatch)
sub push_inbox {
    my ($self, $packet) = @_;
    push @{$self->{inbox}}, $packet;
}

# Send a request (raw payload bytes), return message_id
sub send_request {
    my ($self, $payload) = @_;
    croak "Stream $self->{stream_id} is closed" if $self->{closed};

    my $msg_id = $self->{next_message_id}++;
    $self->{connection}->send_packet({
        stream_id  => $self->{stream_id},
        message_id => $msg_id,
        is_reply   => 0,
        payload    => $payload,
    });
    return $msg_id;
}

# Send a reply (raw payload bytes) to a specific message
sub write_reply {
    my ($self, $message_id, $payload) = @_;
    $self->{connection}->send_packet({
        stream_id  => $self->{stream_id},
        message_id => $message_id,
        is_reply   => 1,
        payload    => $payload,
    });
}

# Wait for a reply to a specific message_id
sub receive_reply {
    my ($self, $expected_msg_id) = @_;

    # First check inbox for an already-received reply
    for my $i (0 .. $#{$self->{inbox}}) {
        my $pkt = $self->{inbox}[$i];
        if ($pkt->{is_reply} && $pkt->{message_id} == $expected_msg_id) {
            splice(@{$self->{inbox}}, $i, 1);
            return $pkt->{payload};
        }
    }

    # Read from connection until we get our reply
    while (1) {
        my $pkt = $self->{connection}->read_packet_for_stream($self->{stream_id});
        if ($pkt->{is_reply} && $pkt->{message_id} == $expected_msg_id) {
            return $pkt->{payload};
        }
        # Got a packet for this stream but not the reply we want - stash it
        push @{$self->{inbox}}, $pkt;
    }
}

# Wait for an incoming request (non-reply packet)
sub receive_request {
    my ($self) = @_;

    # Check inbox first
    for my $i (0 .. $#{$self->{inbox}}) {
        my $pkt = $self->{inbox}[$i];
        if (!$pkt->{is_reply}) {
            splice(@{$self->{inbox}}, $i, 1);
            return ($pkt->{message_id}, $pkt->{payload});
        }
    }

    # Read from connection
    while (1) {
        my $pkt = $self->{connection}->read_packet_for_stream($self->{stream_id});
        if (!$pkt->{is_reply}) {
            return ($pkt->{message_id}, $pkt->{payload});
        }
        push @{$self->{inbox}}, $pkt;
    }
}

# High-level: send CBOR request, get CBOR reply.
# Extracts the "result" field from the standard {result: value} / {error: msg} envelope.
sub request_cbor {
    my ($self, $data) = @_;
    my $payload = cbor_encode($data);
    my $msg_id = $self->send_request($payload);
    my $reply_bytes = $self->receive_reply($msg_id);
    my $reply = cbor_decode($reply_bytes);

    # Handle the result/error envelope
    if (ref $reply eq 'HASH') {
        if (exists $reply->{error}) {
            return $reply;  # Return the full error map for error handling
        }
        if (exists $reply->{result}) {
            return $reply->{result};
        }
    }
    return $reply;
}

# Close the stream gracefully
sub close_stream {
    my ($self) = @_;
    return if $self->{closed};
    eval {
        $self->{connection}->send_packet({
            stream_id  => $self->{stream_id},
            message_id => CLOSE_STREAM_MESSAGE_ID,
            is_reply   => 0,
            payload    => CLOSE_STREAM_PAYLOAD,
        });
    };
    $self->{closed} = 1;
    $self->{connection}->unregister_stream($self->{stream_id});
}

1;
