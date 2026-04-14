use strict;
use warnings;
use JSON::XS qw(decode_json encode_json);

use Hegel::Runner;
use Hegel::Generators::Primitives qw(booleans integers);
use Hegel::Generators::Collections qw(lists);

my $params_json = $ARGV[0] || '{}';
my $params = decode_json($params_json);

my $metrics_file = $ENV{CONFORMANCE_METRICS_FILE} or die "CONFORMANCE_METRICS_FILE not set";
my $test_cases = ($ENV{CONFORMANCE_TEST_CASES} || 50) + 0;

open(my $metrics_fh, '>', $metrics_file) or die "Cannot open $metrics_file: $!";

my $test_mode = $ENV{HEGEL_PROTOCOL_TEST_MODE} || '';

# Choose generator based on test mode:
# - Collection modes need a compositional list generator to exercise the collection protocol
# - Other modes just need any generator
my $gen;
if ($test_mode =~ /collection/) {
    # Force compositional path by wrapping in filter
    $gen = lists(integers(min_value => 0, max_value => 100)->filter(sub { 1 }),
                 min_size => 1, max_size => 5);
} else {
    $gen = booleans();
}

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        print $metrics_fh encode_json({}) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };

close($metrics_fh);
exit 0;
