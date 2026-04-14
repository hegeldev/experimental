package Hegel::Session;
use strict;
use warnings;

use Carp qw(croak);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use File::Path qw(make_path);

use Hegel::Connection;
use Hegel::Protocol qw(cbor_encode cbor_decode);

# Supported protocol version range
use constant MIN_PROTOCOL_VERSION => "0.10";
use constant MAX_PROTOCOL_VERSION => "0.10";
use constant HEGEL_SERVER_VERSION => "0.4.1";
use constant HANDSHAKE_STRING     => "hegel_handshake_start";

# Global singleton session
my $_session;

sub get {
    my ($class) = @_;
    return $_session if $_session;
    $_session = $class->_init();
    return $_session;
}

sub _init {
    my ($class) = @_;

    # Determine server command
    my $server_cmd = $ENV{HEGEL_SERVER_COMMAND};
    my @cmd;
    if ($server_cmd) {
        @cmd = ($server_cmd, '--stdio', '--verbosity', 'normal');
    } else {
        @cmd = ('uv', 'tool', 'run', '--from',
                'hegel-core==' . HEGEL_SERVER_VERSION,
                'hegel', '--stdio', '--verbosity', 'normal');
    }

    # Create log directory
    make_path('.hegel') unless -d '.hegel';

    # Spawn the server subprocess
    my $stderr_fh = gensym;
    my $pid = open3(my $stdin, my $stdout, $stderr_fh, @cmd);

    # Set up stderr logging
    my $log_ix = 0;
    $log_ix++ while -e ".hegel/server.$$-$log_ix.log";
    if (open(my $log_fh, '>', ".hegel/server.$$-$log_ix.log")) {
        # Fork a child to drain stderr to log file
        # (non-blocking approach: we won't drain continuously,
        # but the OS buffer should handle it for our use case)
        $log_fh->autoflush(1);
        # We'll drain stderr periodically or let it buffer
        # For now, store the handle for later cleanup
    }

    binmode $stdin;
    binmode $stdout;
    $stdin->autoflush(1);

    # Create connection
    my $connection = Hegel::Connection->new(
        reader => $stdout,
        writer => $stdin,
    );
    my $control = $connection->control_stream();

    # Perform handshake
    my $msg_id = $control->send_request(HANDSHAKE_STRING);
    my $response;
    eval {
        $response = $control->receive_reply($msg_id);
    };
    if ($@) {
        kill 'TERM', $pid;
        waitpid($pid, 0);
        croak "Hegel server handshake failed: $@\n"
            . "Make sure hegel-core is installed: uv tool install hegel-core==" . HEGEL_SERVER_VERSION;
    }

    # Validate protocol version
    my $version_str = $response;
    unless ($version_str =~ m{^Hegel/(\d+\.\d+)$}) {
        kill 'TERM', $pid;
        waitpid($pid, 0);
        croak "Bad handshake response: '$version_str'";
    }
    my $server_version = $1;
    my $sv = _parse_version($server_version);
    my $min = _parse_version(MIN_PROTOCOL_VERSION);
    my $max = _parse_version(MAX_PROTOCOL_VERSION);
    if ($sv < $min || $sv > $max) {
        kill 'TERM', $pid;
        waitpid($pid, 0);
        croak "Unsupported protocol version: $server_version "
            . "(supported: " . MIN_PROTOCOL_VERSION . " - " . MAX_PROTOCOL_VERSION . ")";
    }

    my $self = bless {
        pid        => $pid,
        connection => $connection,
        control    => $control,
        stderr_fh  => $stderr_fh,
    }, $class;

    return $self;
}

sub connection { $_[0]->{connection} }
sub control    { $_[0]->{control} }

sub _parse_version {
    my ($v) = @_;
    my ($major, $minor) = split /\./, $v;
    return $major * 1000 + $minor;
}

# Cleanup on destruction
sub DESTROY {
    my ($self) = @_;
    return unless $self->{pid};
    eval {
        $self->{connection}->close() if $self->{connection};
    };
    eval {
        kill 'TERM', $self->{pid};
        waitpid($self->{pid}, 0);
    };
    $self->{pid} = undef;
}

# Also clean up on program exit
END {
    if ($_session) {
        eval { $_session->DESTROY() };
        $_session = undef;
    }
}

1;
