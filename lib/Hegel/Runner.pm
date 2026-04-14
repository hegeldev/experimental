package Hegel::Runner;
use strict;
use warnings;

use Carp qw(croak);
use Hegel::Session;
use Hegel::TestCase;
use Hegel::Protocol qw(cbor_encode cbor_decode);

sub new {
    my ($class, %args) = @_;
    return bless {
        test_fn    => $args{test_fn},
        settings   => $args{settings} || {},
    }, $class;
}

sub run {
    my ($self) = @_;

    my $session = Hegel::Session->get();
    my $connection = $session->connection();
    my $control = $session->control();

    # Allocate a test stream
    my $test_stream = $connection->new_stream();

    # Build run_test request
    my $settings = $self->{settings};
    my $run_test = {
        command    => 'run_test',
        stream_id  => $test_stream->stream_id(),
        test_cases => $settings->{test_cases} || 100,
    };
    $run_test->{seed} = $settings->{seed} if defined $settings->{seed};
    $run_test->{derandomize} = ($settings->{derandomize} ? \1 : \0)
        if defined $settings->{derandomize};
    if (defined $settings->{database}) {
        $run_test->{database} = $settings->{database};
    }
    if (defined $settings->{database_key}) {
        $run_test->{database_key} = $settings->{database_key};
    }
    if ($settings->{suppress_health_check}) {
        $run_test->{suppress_health_check} = $settings->{suppress_health_check};
    }

    # Send run_test on control stream
    my $response = $control->request_cbor($run_test);

    # Event loop: process test_case and test_done events
    my $failure_message;
    my $error_message;
    my $passed = 1;

    while (1) {
        my ($msg_id, $payload_bytes) = $test_stream->receive_request();
        my $event = cbor_decode($payload_bytes);

        my $event_type = $event->{event} || '';

        if ($event_type eq 'test_done') {
            # Acknowledge test_done
            $test_stream->write_reply($msg_id, cbor_encode({ result => \1 }));

            # Process results
            my $results = $event->{results} || {};
            if ($results->{error}) {
                $error_message = $results->{error};
                $passed = 0;
            }
            if ($results->{health_check_failure}) {
                $error_message = "Health check failure: " . join(', ', @{$results->{health_check_failure}});
                $passed = 0;
            }
            if ($results->{flaky}) {
                $error_message = "Flaky test detected";
                $passed = 0;
            }

            # Handle final replay of interesting test cases
            my $interesting = $results->{interesting_test_cases};
            if ($interesting && @$interesting) {
                for my $tc_info (@$interesting) {
                    my ($replay_msg_id, $replay_bytes) = $test_stream->receive_request();
                    my $replay_event = cbor_decode($replay_bytes);
                    # Acknowledge
                    $test_stream->write_reply($replay_msg_id, cbor_encode({ result => \1 }));

                    my $tc_stream_id = $replay_event->{stream_id};
                    my $tc_stream = $connection->connect_stream($tc_stream_id);
                    my $tc = Hegel::TestCase->new(
                        stream   => $tc_stream,
                        is_final => 1,
                    );

                    eval { $self->{test_fn}->($tc) };
                    my $err = $@;

                    if ($err && ref $err && $err->isa('Hegel::UnsatisfiedAssumption')) {
                        $tc->mark_complete('INVALID', 'REPLAY');
                    } elsif ($err && ref $err && $err->isa('Hegel::StopTest')) {
                        # Don't send mark_complete after StopTest
                    } elsif ($err) {
                        $failure_message = "$err";
                        $tc->mark_complete('INTERESTING', 'REPLAY');
                        $tc->print_draws();
                        $tc->print_notes();
                    } else {
                        $tc->mark_complete('VALID', 'REPLAY');
                    }
                }
            }

            last;
        }

        if ($event_type eq 'test_case') {
            # Acknowledge the test case event BEFORE running (prevents deadlock)
            $test_stream->write_reply($msg_id, cbor_encode({ result => \1 }));

            my $tc_stream_id = $event->{stream_id};
            my $is_final = $event->{is_final} ? 1 : 0;
            my $tc_stream = $connection->connect_stream($tc_stream_id);
            my $tc = Hegel::TestCase->new(
                stream   => $tc_stream,
                is_final => $is_final,
            );

            # Run the test function
            eval { $self->{test_fn}->($tc) };
            my $err = $@;

            if ($err && ref $err && $err->isa('Hegel::UnsatisfiedAssumption')) {
                $tc->mark_complete('INVALID', 'HEGEL');
            } elsif ($err && ref $err && $err->isa('Hegel::StopTest')) {
                # Don't send mark_complete after StopTest
            } elsif ($err) {
                $tc->mark_complete('INTERESTING', 'HEGEL');
            } else {
                $tc->mark_complete('VALID', 'HEGEL');
            }
        }
    }

    $test_stream->close_stream();

    return {
        passed          => $passed,
        failure_message => $failure_message,
        error_message   => $error_message,
    };
}

1;
