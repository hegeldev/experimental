#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel::Protocol qw(read_packet write_packet cbor_encode cbor_decode MAGIC REPLY_BIT);

# --- CBOR round-trip tests ---

subtest 'cbor encode/decode simple map' => sub {
    my $data = { type => 'integer', min_value => 0, max_value => 100 };
    my $encoded = cbor_encode($data);
    my $decoded = cbor_decode($encoded);
    is($decoded->{type}, 'integer');
    is($decoded->{min_value}, 0);
    is($decoded->{max_value}, 100);
};

subtest 'cbor encode/decode nested map' => sub {
    my $data = { command => 'generate', schema => { type => 'float' } };
    my $encoded = cbor_encode($data);
    my $decoded = cbor_decode($encoded);
    is($decoded->{command}, 'generate');
    is($decoded->{schema}{type}, 'float');
};

subtest 'cbor encode/decode with arrays' => sub {
    my $data = { elements => [1, 2, 'three'] };
    my $encoded = cbor_encode($data);
    my $decoded = cbor_decode($encoded);
    is_deeply($decoded->{elements}, [1, 2, 'three']);
};

subtest 'cbor encode/decode null' => sub {
    my $data = { value => undef };
    my $encoded = cbor_encode($data);
    my $decoded = cbor_decode($encoded);
    ok(!defined $decoded->{value});
};

subtest 'cbor encode/decode booleans' => sub {
    use Types::Serialiser;
    my $data = { t => Types::Serialiser::true, f => Types::Serialiser::false };
    my $encoded = cbor_encode($data);
    my $decoded = cbor_decode($encoded);
    ok($decoded->{t}, 'true is truthy');
    ok(!$decoded->{f}, 'false is falsy');
};

# --- Packet round-trip tests ---

subtest 'packet round-trip' => sub {
    pipe(my $rd, my $wr) or die "pipe: $!";
    $wr->autoflush(1);

    my $payload = cbor_encode({ command => 'test' });
    write_packet($wr, {
        stream_id  => 5,
        message_id => 3,
        is_reply   => 0,
        payload    => $payload,
    });

    my $pkt = read_packet($rd);
    is($pkt->{stream_id}, 5);
    is($pkt->{message_id}, 3);
    is($pkt->{is_reply}, 0);
    is($pkt->{payload}, $payload);

    close $wr;
    close $rd;
};

subtest 'packet with reply bit' => sub {
    pipe(my $rd, my $wr) or die "pipe: $!";
    $wr->autoflush(1);

    write_packet($wr, {
        stream_id  => 0,
        message_id => 7,
        is_reply   => 1,
        payload    => 'ok',
    });

    my $pkt = read_packet($rd);
    is($pkt->{stream_id}, 0);
    is($pkt->{message_id}, 7);
    is($pkt->{is_reply}, 1);
    is($pkt->{payload}, 'ok');

    close $wr;
    close $rd;
};

subtest 'packet with empty payload' => sub {
    pipe(my $rd, my $wr) or die "pipe: $!";
    $wr->autoflush(1);

    write_packet($wr, {
        stream_id  => 0,
        message_id => 0,
        is_reply   => 0,
        payload    => '',
    });

    my $pkt = read_packet($rd);
    is($pkt->{payload}, '');

    close $wr;
    close $rd;
};

subtest 'invalid magic detected' => sub {
    pipe(my $rd, my $wr) or die "pipe: $!";
    $wr->autoflush(1);

    # Write a packet with wrong magic
    my $bad_header = pack("NNNNN", 0xDEADBEEF, 0, 0, 0, 0);
    syswrite($wr, $bad_header . chr(0x0A));

    throws_ok { read_packet($rd) } qr/Invalid magic/;

    close $wr;
    close $rd;
};

subtest 'CRC32 mismatch detected' => sub {
    pipe(my $rd, my $wr) or die "pipe: $!";
    $wr->autoflush(1);

    # Write a packet with correct magic but wrong CRC
    my $payload = 'test';
    my $header = pack("NNNNN", MAGIC, 0xBADBAD, 0, 0, length($payload));
    syswrite($wr, $header . $payload . chr(0x0A));

    throws_ok { read_packet($rd) } qr/CRC32 mismatch/;

    close $wr;
    close $rd;
};

done_testing;
