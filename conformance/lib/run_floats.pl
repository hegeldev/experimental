use strict;
use warnings;
use JSON::XS qw(decode_json encode_json);
use POSIX qw(isinf isnan);

use Hegel::Runner;
use Hegel::Generators::Primitives qw(floats);

my $params_json = $ARGV[0] || '{}';
my $params = decode_json($params_json);

my $metrics_file = $ENV{CONFORMANCE_METRICS_FILE} or die "CONFORMANCE_METRICS_FILE not set";
my $test_cases = ($ENV{CONFORMANCE_TEST_CASES} || 50) + 0;

open(my $metrics_fh, '>', $metrics_file) or die "Cannot open $metrics_file: $!";

my %gen_args;
$gen_args{min_value} = $params->{min_value} + 0.0 if defined $params->{min_value};
$gen_args{max_value} = $params->{max_value} + 0.0 if defined $params->{max_value};
# exclude_min/exclude_max are booleans; only set when true
$gen_args{exclude_min} = 1 if $params->{exclude_min};
$gen_args{exclude_max} = 1 if $params->{exclude_max};
# allow_nan and allow_infinity are ternary: true, false, or null (omit)
$gen_args{allow_nan} = $params->{allow_nan} if defined $params->{allow_nan};
$gen_args{allow_infinity} = $params->{allow_infinity} if defined $params->{allow_infinity};

my $gen = floats(%gen_args);

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        my %metrics;
        if (isnan($val)) {
            $metrics{is_nan} = \1;
        } elsif (isinf($val)) {
            $metrics{is_infinite} = \1;
            $metrics{value} = $val + 0.0;
        } else {
            $metrics{value} = $val + 0.0;
        }
        print $metrics_fh encode_json(\%metrics) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };
warn "Error: $@" if $@;

close($metrics_fh);
exit 0;
