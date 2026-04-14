use strict;
use warnings;
use JSON::XS qw(decode_json encode_json);

use Hegel::Runner;
use Hegel::Generators::Primitives qw(binary);

my $params_json = $ARGV[0] || '{}';
my $params = decode_json($params_json);

my $metrics_file = $ENV{CONFORMANCE_METRICS_FILE} or die "CONFORMANCE_METRICS_FILE not set";
my $test_cases = ($ENV{CONFORMANCE_TEST_CASES} || 50) + 0;

open(my $metrics_fh, '>', $metrics_file) or die "Cannot open $metrics_file: $!";

my %gen_args;
$gen_args{min_size} = ($params->{min_size} + 0) if defined $params->{min_size};
$gen_args{max_size} = ($params->{max_size} + 0) if defined $params->{max_size};

my $gen = binary(%gen_args);

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        print $metrics_fh encode_json({ length => length($val) + 0 }) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };

close($metrics_fh);
exit 0;
