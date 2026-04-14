#!/usr/bin/env perl
# Tests exercising error paths, failure detection, and edge cases.
use strict;
use warnings;
use Test::More;

use lib 'lib';
use Hegel qw(:all);
use Hegel::Runner;

# Test that a failing property is detected
subtest 'failing property detected' => sub {
    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $x = $tc->draw(integers(min_value => 0, max_value => 100));
            die "intentional failure" if $x > 5;
        },
        settings => { test_cases => 100 },
    );
    my $result = $runner->run();
    ok(!$result->{passed}, "failure detected");
    ok(defined $result->{failure_message}, "failure message set");
    like($result->{failure_message}, qr/intentional failure/, "correct message");
};

# Test assume rejection
subtest 'assume rejection is not a failure' => sub {
    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $x = $tc->draw(integers(min_value => 0, max_value => 10));
            $tc->assume($x > 5);  # reject ~60% of cases
            ok($x > 5);
        },
        settings => { test_cases => 50 },
    );
    my $result = $runner->run();
    ok($result->{passed}, "test passes (non-rejected cases all valid)");
};

# Test with derandomize setting
subtest 'derandomize setting' => sub {
    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            my $x = $tc->draw(integers(min_value => 0, max_value => 100));
            ok(1);
        },
        settings => { test_cases => 3, derandomize => 1 },
    );
    my $result = $runner->run();
    ok($result->{passed}, "derandomize test passes");
};

# Test Generator base class do_draw throws
subtest 'base Generator do_draw throws' => sub {
    my $gen = Hegel::Generator->new();
    eval { $gen->do_draw(undef) };
    like($@, qr/not implemented/, "base do_draw throws");
};

# Exercise is_closed on stream
subtest 'stream is_closed' => sub {
    use Hegel::Stream;
    use Hegel::Connection;
    pipe(my $rd, my $wr) or die;
    $wr->autoflush(1);
    my $conn = Hegel::Connection->new(reader => $rd, writer => $wr);
    my $stream = $conn->control_stream();
    ok(!$stream->is_closed, "stream starts open");
    $stream->mark_closed();
    ok($stream->is_closed, "stream is closed after mark_closed");
    close $wr; close $rd;
};

# Test with seed and suppress_health_check settings
subtest 'seed and suppress_health_check' => sub {
    my $runner = Hegel::Runner->new(
        test_fn => sub {
            my ($tc) = @_;
            $tc->draw(integers(min_value => 0, max_value => 10));
        },
        settings => { test_cases => 3, seed => 42, suppress_health_check => ['too_slow'] },
    );
    my $result = $runner->run();
    ok($result->{passed}, "passes with seed + suppress_health_check");
};

done_testing;
