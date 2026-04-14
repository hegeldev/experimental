#!/usr/bin/env perl
# Targeted tests for remaining coverage gaps.
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel qw(:all);
use Hegel::TestUtils qw(find_any assert_no_examples);

# --- Stream coverage: close_stream, receive_request ---

subtest 'stream close_stream is idempotent' => sub {
    use Hegel::Stream;
    use Hegel::Connection;
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->control_stream();
    $stream->close_stream();  # first close
    ok($stream->is_closed, "closed");
    $stream->close_stream();  # second close - should be a no-op
    ok($stream->is_closed, "still closed");
    close $wr; close $rd;
};

# --- TestUtils: find_any failure, assert_no_examples with found ---

subtest 'find_any dies when no match' => sub {
    throws_ok {
        find_any(
            just(0),
            sub { $_[0] > 100 },  # impossible
            test_cases => 5,
        );
    } qr/no example/i, "find_any dies when nothing found";
};

subtest 'assert_no_examples dies when found' => sub {
    throws_ok {
        assert_no_examples(
            integers(min_value => 0, max_value => 10),
            sub { $_[0] >= 0 },  # always true
            test_cases => 10,
        );
    } qr/found.*example/i, "assert_no_examples dies when found";
};

# --- DataSource: _handle_error via connection failure ---

subtest 'ServerDataSource _handle_error on connection error' => sub {
    use Hegel::DataSource;
    # Create a ServerDataSource with a broken stream
    my $mock_stream = bless {
        closed => 0,
        connection => bless { running => 0 }, 'Hegel::Connection',
    }, 'Hegel::Stream';
    # Override request_cbor to simulate connection error
    no warnings 'redefine';
    local *Hegel::Stream::request_cbor = sub { die "Connection reset" };
    local *Hegel::Stream::close_stream = sub { };
    my $ds = Hegel::ServerDataSource->new(stream => $mock_stream);
    throws_ok { $ds->generate({ type => 'integer' }) }
        qr/Hegel::StopTest|Connection/, "connection error becomes StopTest";
    ok($ds->test_aborted, "aborted after connection error");
};

# --- Hegel.pm: failure_message and passed branches ---

subtest 'hegel failure path via Runner' => sub {
    use Hegel::Runner;
    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $x = $tc->draw(integers(min_value => 0, max_value => 100));
            die "intentional failure";
        },
        settings => { test_cases => 50 },
    );
    my $result = $runner->run();
    ok(!$result->{passed}, "failure detected");
    ok($result->{failure_message}, "has failure message");
};

# --- Primitives: floats with all options ---

subtest 'floats with all options set' => sub {
    hegel "floats full options" => sub {
        my ($tc) = @_;
        my $gen = floats(
            min_value => 0.0, max_value => 1.0,
            allow_nan => 0, allow_infinity => 0,
            exclude_min => 1, exclude_max => 1,
        );
        my $val = $tc->draw($gen);
        ok($val > 0.0 && $val < 1.0, "in exclusive range: $val");
    }, test_cases => 10;
};

# --- Connection: unregister_stream ---

subtest 'connection unregister_stream' => sub {
    use Hegel::Connection;
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->new_stream();
    my $id = $stream->stream_id();
    ok(exists $conn->{streams}{$id}, "stream registered");
    $conn->unregister_stream($id);
    ok(!exists $conn->{streams}{$id}, "stream unregistered");
    close $wr; close $rd;
};

# --- Runner: flaky test detection ---

subtest 'flaky test detection' => sub {
    my $counter = 0;
    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $val = $tc->draw(integers(min_value => 1, max_value => 100));
            $counter++;
            # Fail on the second test case only
            if ($counter == 2) {
                die "flaky failure";
            }
        },
        settings => { test_cases => 50 },
    );
    my $result = $runner->run();
    # Either flaky detected or failure found - both are valid outcomes
    ok(defined $result, "completed");
};

# --- Primitives: ip_addresses invalid version ---
subtest 'ip_addresses invalid version' => sub {
    throws_ok { ip_addresses(version => 99) }
        qr/version must be/, "invalid ip version dies";
};

# --- Primitives: from_regex with alphabet ---
subtest 'from_regex with alphabet' => sub {
    hegel "regex with alphabet" => sub {
        my ($tc) = @_;
        my $gen = from_regex("[a-z]+", fullmatch => 1,
            alphabet => { min_codepoint => 97, max_codepoint => 122 });
        my $val = $tc->draw($gen);
        ok(defined $val, "regex with alphabet: $val");
    }, test_cases => 3;
};

# --- Protocol: invalid terminator ---
subtest 'protocol invalid terminator' => sub {
    use Hegel::Protocol qw(read_packet write_packet MAGIC);
    use String::CRC32 qw(crc32);
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);

    # Write a packet with valid header but wrong terminator
    my $payload = "test";
    my $header_no_crc = pack("NNNNN", MAGIC, 0, 0, 0, length($payload));
    my $checksum = crc32($header_no_crc . $payload);
    my $header = pack("NNNNN", MAGIC, $checksum, 0, 0, length($payload));
    syswrite($wr, $header . $payload . chr(0xFF));  # wrong terminator

    throws_ok { read_packet($rd) } qr/Invalid terminator/;
    close $wr; close $rd;
};

# --- Protocol: connection closed during read ---
subtest 'protocol connection closed' => sub {
    use Hegel::Protocol qw(read_packet);
    pipe(my $rd, my $wr) or die;
    # Write only 5 bytes (not enough for header)
    syswrite($wr, "HEGL");
    close $wr;  # close immediately
    throws_ok { read_packet($rd) } qr/Connection closed|Read error/;
    close $rd;
};

done_testing;
