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
# Only set exclude_min/exclude_max when true
$gen_args{exclude_min} = 1 if $params->{exclude_min};
$gen_args{exclude_max} = 1 if $params->{exclude_max};
# allow_nan and allow_infinity are ternary: true, false, or null (omit)
$gen_args{allow_nan} = $params->{allow_nan} if defined $params->{allow_nan};
$gen_args{allow_infinity} = $params->{allow_infinity} if defined $params->{allow_infinity};

# Format a float64 as the shortest decimal string that round-trips exactly.
# This matches Python's repr() behavior.
sub _float_repr {
    my ($v) = @_;
    my $packed = pack("d", $v);
    for my $digits (1..20) {
        my $s = sprintf("%.*g", $digits, $v);
        # Check if parsing this string back gives the same float64
        my $repacked = pack("d", $s + 0.0);
        return $s if $repacked eq $packed;
    }
    return sprintf("%.20g", $v);  # fallback
}

my $gen = floats(%gen_args);

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        my $line;
        if (isnan($val)) {
            $line = '{"is_nan":true}';
        } elsif (isinf($val)) {
            $line = '{"is_infinite":true}';
        } else {
            # Format float with minimum digits for exact round-trip.
            # %.17g can produce representations that Python's json.loads
            # maps to a different float64. Use shortest-exact format.
            $line = sprintf '{"value":%s}', _float_repr($val);
        }
        print $metrics_fh "$line\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };
if ($@) { warn "Error: $@"; }

close($metrics_fh);
exit 0;
