package Hegel::Protocol;
use strict;
use warnings;

use CBOR::XS ();
use String::CRC32 qw(crc32);
use Carp qw(croak);

use Exporter 'import';
our @EXPORT_OK = qw(
    read_packet write_packet
    cbor_encode cbor_decode
    MAGIC REPLY_BIT HEADER_SIZE TERMINATOR
    CLOSE_STREAM_MESSAGE_ID CLOSE_STREAM_PAYLOAD
);

use constant MAGIC       => 0x4845474C;  # "HEGL"
use constant REPLY_BIT   => 0x80000000;
use constant HEADER_SIZE => 20;
use constant TERMINATOR  => 0x0A;

# Special packet values for closing a stream
use constant CLOSE_STREAM_MESSAGE_ID => 0x7FFFFFFF;
use constant CLOSE_STREAM_PAYLOAD    => pack("C", 0xFE);

# CBOR Tag 91 for WTF-8 strings (Hegel string tag)
use constant HEGEL_STRING_TAG => 91;

# --- Packet I/O ---

sub read_exact {
    my ($fh, $n) = @_;
    my $buf = '';
    while (length($buf) < $n) {
        my $bytes_read = sysread($fh, my $chunk, $n - length($buf));
        if (!defined $bytes_read) {
            croak "Read error: $!";
        }
        if ($bytes_read == 0) {
            croak "Connection closed during read (got " . length($buf) . " of $n bytes)";
        }
        $buf .= $chunk;
    }
    return $buf;
}

sub read_packet {
    my ($fh) = @_;

    # Read 20-byte header
    my $header = read_exact($fh, HEADER_SIZE);
    my ($magic, $checksum, $stream_id, $raw_message_id, $payload_length) =
        unpack("NNNNN", $header);

    if ($magic != MAGIC) {
        croak sprintf("Invalid magic: 0x%08X (expected 0x%08X)", $magic, MAGIC);
    }

    # Read payload + terminator
    my $payload = '';
    if ($payload_length > 0) {
        $payload = read_exact($fh, $payload_length);
    }
    my $term = read_exact($fh, 1);
    if (ord($term) != TERMINATOR) {
        croak sprintf("Invalid terminator: 0x%02X (expected 0x0A)", ord($term));
    }

    # Verify CRC32
    my $check_header = substr($header, 0, 4) . ("\0" x 4) . substr($header, 8);
    my $expected_crc = crc32($check_header . $payload);
    if ($checksum != $expected_crc) {
        croak sprintf("CRC32 mismatch: got 0x%08X, expected 0x%08X",
            $checksum, $expected_crc);
    }

    # Parse reply bit from message ID
    my $is_reply = ($raw_message_id & REPLY_BIT) ? 1 : 0;
    my $message_id = $raw_message_id & 0x7FFFFFFF;

    return {
        stream_id  => $stream_id,
        message_id => $message_id,
        is_reply   => $is_reply,
        payload    => $payload,
    };
}

sub write_packet {
    my ($fh, $packet) = @_;

    my $stream_id  = $packet->{stream_id};
    my $message_id = $packet->{message_id};
    my $is_reply   = $packet->{is_reply} || 0;
    my $payload    = $packet->{payload};

    my $raw_message_id = $message_id;
    if ($is_reply) {
        $raw_message_id = ($message_id | REPLY_BIT) & 0xFFFFFFFF;
    }

    # Build header with zeroed CRC for checksum calculation
    my $header_no_crc = pack("NNNNN",
        MAGIC, 0, $stream_id, $raw_message_id, length($payload));

    my $checksum = crc32($header_no_crc . $payload);

    # Build final header with CRC
    my $header = pack("NNNNN",
        MAGIC, $checksum, $stream_id, $raw_message_id, length($payload));

    # Write atomically: header + payload + terminator
    my $data = $header . $payload . chr(TERMINATOR);
    my $written = 0;
    while ($written < length($data)) {
        my $n = syswrite($fh, $data, length($data) - $written, $written);
        if (!defined $n) {
            croak "Write error: $!";
        }
        $written += $n;
    }
}

# --- CBOR helpers ---

# CBOR encoder. Tag 91 is only used by the SERVER for WTF-8 strings;
# the client sends standard CBOR with text strings (major type 3).
# We use CBOR::XS for encoding with text_strings mode enabled.

my $cbor_encoder = CBOR::XS->new->text_strings(1);

# CBOR decoder with Tag 91 filter - automatically unwraps tagged strings
my $cbor_decoder = CBOR::XS->new->filter(sub {
    my ($tag, $data) = @_;
    return $data if $tag == HEGEL_STRING_TAG;
    return CBOR::XS::tag($tag, $data);
});

sub cbor_encode {
    my ($data) = @_;
    return $cbor_encoder->encode($data);
}

sub cbor_decode {
    my ($bytes) = @_;
    return $cbor_decoder->decode($bytes);
}

1;
