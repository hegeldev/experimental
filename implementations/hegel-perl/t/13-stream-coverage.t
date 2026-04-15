#!/usr/bin/env perl
# Tests for Stream coverage gaps.
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel::Protocol qw(write_packet read_packet REPLY_BIT);
use Hegel::Connection;
use Hegel::Stream;

# --- Send on closed stream ---
subtest 'send_request on closed stream dies' => sub {
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->new_stream();
    $stream->mark_closed();
    throws_ok { $stream->send_request("test") } qr/closed/;
    close $wr; close $rd;
};

# --- Receive reply from inbox (pre-stashed packet) ---
subtest 'receive_reply finds packet in inbox' => sub {
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->new_stream();
    my $sid = $stream->stream_id();

    # Pre-stash a reply packet in the stream's inbox
    push @{$stream->{inbox}}, {
        stream_id  => $sid,
        message_id => 42,
        is_reply   => 1,
        payload    => "inbox_reply",
    };

    my $reply = $stream->receive_reply(42);
    is($reply, "inbox_reply", "found reply in inbox");
    close $wr; close $rd;
};

# --- Receive reply stashes non-matching packets ---
subtest 'receive_reply stashes non-matching packet' => sub {
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->new_stream();
    my $sid = $stream->stream_id();

    # Write a non-reply packet (request) for this stream, then the actual reply
    write_packet($wr, {
        stream_id => $sid, message_id => 0, is_reply => 0, payload => "request",
    });
    write_packet($wr, {
        stream_id => $sid, message_id => 5, is_reply => 1, payload => "the_reply",
    });

    my $reply = $stream->receive_reply(5);
    is($reply, "the_reply", "got correct reply after stashing request");
    # The stashed request should be in the inbox
    is(scalar @{$stream->{inbox}}, 1, "request stashed in inbox");
    is($stream->{inbox}[0]{payload}, "request", "stashed request is correct");
    close $wr; close $rd;
};

# --- Receive request from inbox ---
subtest 'receive_request finds packet in inbox' => sub {
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->new_stream();
    my $sid = $stream->stream_id();

    # Pre-stash a request in inbox
    push @{$stream->{inbox}}, {
        stream_id  => $sid,
        message_id => 7,
        is_reply   => 0,
        payload    => "stashed_request",
    };

    my ($msg_id, $payload) = $stream->receive_request();
    is($msg_id, 7, "got stashed request msg_id");
    is($payload, "stashed_request", "got stashed request payload");
    close $wr; close $rd;
};

# --- Receive request stashes reply packets ---
subtest 'receive_request stashes replies' => sub {
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->new_stream();
    my $sid = $stream->stream_id();

    # Write a reply first, then a request
    write_packet($wr, {
        stream_id => $sid, message_id => 10, is_reply => 1, payload => "a_reply",
    });
    write_packet($wr, {
        stream_id => $sid, message_id => 3, is_reply => 0, payload => "a_request",
    });

    my ($msg_id, $payload) = $stream->receive_request();
    is($msg_id, 3, "got request after stashing reply");
    is(scalar @{$stream->{inbox}}, 1, "reply stashed");
    close $wr; close $rd;
};

done_testing;
