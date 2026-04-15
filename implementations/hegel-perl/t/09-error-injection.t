#!/usr/bin/env perl
# Tests exercising error injection via HEGEL_PROTOCOL_TEST_MODE.
# Each test needs a fresh session because the test-mode server handles
# exactly one run_test then exits.
use strict;
use warnings;
use Test::More;

use lib 'lib';
use Hegel::Session;
use Hegel::Runner;
use Hegel::Generators::Primitives qw(integers booleans);
use Hegel::Generators::Collections qw(lists);

sub run_with_mode {
    my ($mode, $test_fn, %opts) = @_;
    local $ENV{HEGEL_PROTOCOL_TEST_MODE} = $mode;
    Hegel::Session->reset();
    my $runner = Hegel::Runner->new(
        test_fn  => $test_fn,
        settings => { test_cases => $opts{test_cases} || 10 },
    );
    my $result = eval { $runner->run() };
    my $err = $@;
    Hegel::Session->reset();
    return ($result, $err);
}

subtest 'stop_test_on_generate' => sub {
    my ($result, $err) = run_with_mode('stop_test_on_generate', sub {
        my ($tc) = @_;
        $tc->draw(integers(min_value => 0, max_value => 100));
    });
    ok(defined $result, "completed without crash");
    ok($result->{passed}, "server reports passed (StopTest is not a failure)");
};

subtest 'stop_test_on_mark_complete' => sub {
    my ($result, $err) = run_with_mode('stop_test_on_mark_complete', sub {
        my ($tc) = @_;
        $tc->draw(integers(min_value => 0, max_value => 100));
    });
    ok(defined $result, "completed without crash");
};

subtest 'error_response' => sub {
    my ($result, $err) = run_with_mode('error_response', sub {
        my ($tc) = @_;
        $tc->draw(integers(min_value => 0, max_value => 100));
    });
    ok(defined $result, "completed without crash");
};

subtest 'empty_test' => sub {
    my ($result, $err) = run_with_mode('empty_test', sub {
        my ($tc) = @_;
        $tc->draw(booleans());
    });
    ok(defined $result, "completed without crash");
    ok($result->{passed}, "empty test passes");
};

subtest 'stop_test_on_collection_more' => sub {
    my ($result, $err) = run_with_mode('stop_test_on_collection_more', sub {
        my ($tc) = @_;
        # Use filtered integers to force collection protocol
        my $elem = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        $tc->draw(lists($elem, min_size => 1, max_size => 5));
    });
    ok(defined $result, "completed without crash");
};

subtest 'stop_test_on_new_collection' => sub {
    my ($result, $err) = run_with_mode('stop_test_on_new_collection', sub {
        my ($tc) = @_;
        my $elem = integers(min_value => 0, max_value => 100)->filter(sub { 1 });
        $tc->draw(lists($elem, min_size => 1, max_size => 5));
    });
    ok(defined $result, "completed without crash");
};

# Restore normal session for subsequent tests
delete $ENV{HEGEL_PROTOCOL_TEST_MODE};
Hegel::Session->reset();

done_testing;
