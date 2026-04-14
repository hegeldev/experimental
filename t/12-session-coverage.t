#!/usr/bin/env perl
# Tests for Session coverage gaps.
use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Hegel::Session;

# --- new_session creates a fresh session ---
subtest 'new_session' => sub {
    my $session = Hegel::Session->new_session();
    ok(defined $session, "new_session returns a session");
    ok(defined $session->connection, "has connection");
    ok(defined $session->control, "has control stream");
    # Clean up
    eval { $session->DESTROY() };
};

# --- HEGEL_SERVER_COMMAND env var ---
# Note: Session._init reads HEGEL_SERVER_COMMAND and passes it as first arg
# followed by --stdio --verbosity normal. The command must accept those flags.
# Skip this test if we can't find a suitable command.
subtest 'HEGEL_SERVER_COMMAND' => sub {
    # Use the same uv command but as a pre-resolved path
    my $hegel_path = `which hegel 2>/dev/null`;
    chomp $hegel_path;
    if (!$hegel_path) {
        # Try uv tool path
        $hegel_path = `uv tool run --from hegel-core==0.4.1 which hegel 2>/dev/null`;
        chomp $hegel_path;
    }
    plan skip_all => "hegel not found on PATH" unless $hegel_path;
    local $ENV{HEGEL_SERVER_COMMAND} = $hegel_path;
    Hegel::Session->reset();
    my $session = eval { Hegel::Session->get() };
    ok(defined $session, "session created with HEGEL_SERVER_COMMAND");
    Hegel::Session->reset();
    delete $ENV{HEGEL_SERVER_COMMAND};
};

# --- Bad server command ---
subtest 'bad server command fails' => sub {
    local $ENV{HEGEL_SERVER_COMMAND} = '/nonexistent/binary';
    Hegel::Session->reset();
    dies_ok { Hegel::Session->get() } "bad server command dies";
    Hegel::Session->reset();
    delete $ENV{HEGEL_SERVER_COMMAND};
};

# --- reset clears singleton ---
subtest 'reset clears singleton' => sub {
    Hegel::Session->reset();
    # After reset, get() creates a new session
    my $s1 = Hegel::Session->get();
    ok(defined $s1, "first get after reset");
    Hegel::Session->reset();
    my $s2 = Hegel::Session->get();
    ok(defined $s2, "second get after reset");
    # They should be different sessions (different PIDs)
    Hegel::Session->reset();
};

# --- Handshake failure with fake server ---
subtest 'handshake failure with fake server' => sub {
    use FindBin qw($RealBin);
    local $ENV{HEGEL_SERVER_COMMAND} = "$RealBin/fake_server.sh";
    Hegel::Session->reset();
    dies_ok { Hegel::Session->get() } "fake server causes handshake failure";
    Hegel::Session->reset();
    delete $ENV{HEGEL_SERVER_COMMAND};
};

# Restore normal session
delete $ENV{HEGEL_SERVER_COMMAND};
delete $ENV{HEGEL_PROTOCOL_TEST_MODE};

done_testing;
