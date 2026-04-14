use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use List::Util qw(min max);

use Hegel::Runner;
use Hegel::Generators::Primitives qw(integers text);
use Hegel::Generators::Collections qw(hashmaps);

my $params_json = $ARGV[0] || '{}';
my $params = decode_json($params_json);

my $metrics_file = $ENV{CONFORMANCE_METRICS_FILE} or die "CONFORMANCE_METRICS_FILE not set";
my $test_cases = ($ENV{CONFORMANCE_TEST_CASES} || 50) + 0;

open(my $metrics_fh, '>', $metrics_file) or die "Cannot open $metrics_file: $!";

my $key_type = $params->{key_type} || 'integer';

my $keys_gen;
if ($key_type eq 'string') {
    $keys_gen = text(min_size => 1, max_size => 10);
} else {
    my %key_args;
    $key_args{min_value} = $params->{min_key} if defined $params->{min_key};
    $key_args{max_value} = $params->{max_key} if defined $params->{max_key};
    $keys_gen = integers(%key_args);
}

my %val_args;
$val_args{min_value} = $params->{min_value} if defined $params->{min_value};
$val_args{max_value} = $params->{max_value} if defined $params->{max_value};
my $vals_gen = integers(%val_args);

# In non_basic mode, force compositional path
my $mode = $params->{mode} || 'basic';
if ($mode eq 'non_basic') {
    $keys_gen = $keys_gen->filter(sub { 1 });
    $vals_gen = $vals_gen->filter(sub { 1 });
}

my %dict_args;
$dict_args{min_size} = ($params->{min_size} + 0) if defined $params->{min_size};
$dict_args{max_size} = ($params->{max_size} + 0) if defined $params->{max_size};

my $gen = hashmaps($keys_gen, $vals_gen, %dict_args);

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        my @keys = keys %$val;
        my @values = values %$val;
        my %metrics = (size => scalar(@keys) + 0);
        if (@keys) {
            if ($key_type eq 'integer') {
                my @int_keys = map { $_ + 0 } @keys;
                $metrics{min_key} = min(@int_keys) + 0;
                $metrics{max_key} = max(@int_keys) + 0;
            }
            my @int_values = map { $_ + 0 } @values;
            $metrics{min_value} = min(@int_values) + 0;
            $metrics{max_value} = max(@int_values) + 0;
        }
        print $metrics_fh encode_json(\%metrics) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };

close($metrics_fh);
exit 0;
