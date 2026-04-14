#!/usr/bin/env perl
# Fake server that replies with a bad handshake string (not "Hegel/...").
use strict;
use warnings;
use lib 'lib';
use Hegel::Protocol qw(read_packet write_packet);
binmode STDIN; binmode STDOUT; STDOUT->autoflush(1);
my $pkt = eval { read_packet(\*STDIN) };
exit 0 unless $pkt;
write_packet(\*STDOUT, {
    stream_id => $pkt->{stream_id}, message_id => $pkt->{message_id},
    is_reply => 1, payload => "GARBAGE_RESPONSE",
});
sleep 5;
