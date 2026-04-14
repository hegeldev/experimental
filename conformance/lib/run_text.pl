use strict;
use warnings;
use JSON::XS qw(decode_json encode_json);

use Hegel::Runner;
use Hegel::Generators::Primitives qw(text);

my $params_json = $ARGV[0] || '{}';
my $params = decode_json($params_json);

my $metrics_file = $ENV{CONFORMANCE_METRICS_FILE} or die "CONFORMANCE_METRICS_FILE not set";
my $test_cases = ($ENV{CONFORMANCE_TEST_CASES} || 50) + 0;

open(my $metrics_fh, '>', $metrics_file) or die "Cannot open $metrics_file: $!";

my %gen_args;
$gen_args{min_size} = ($params->{min_size} + 0) if defined $params->{min_size};
$gen_args{max_size} = ($params->{max_size} + 0) if defined $params->{max_size};
$gen_args{codec} = $params->{codec} if defined $params->{codec};
$gen_args{min_codepoint} = ($params->{min_codepoint} + 0) if defined $params->{min_codepoint};
$gen_args{max_codepoint} = ($params->{max_codepoint} + 0) if defined $params->{max_codepoint};
$gen_args{categories} = $params->{categories} if defined $params->{categories};
$gen_args{exclude_categories} = $params->{exclude_categories} if defined $params->{exclude_categories};
$gen_args{include_characters} = $params->{include_characters} if defined $params->{include_characters};
$gen_args{exclude_characters} = $params->{exclude_characters} if defined $params->{exclude_characters};

my $gen = text(%gen_args);

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        # Report codepoints as an array of integers
        # Must use Unicode-aware decoding for multibyte characters
        use Encode qw(decode);
        my $unicode = eval { decode('UTF-8', $val, Encode::FB_DEFAULT) } // $val;
        my @codepoints = map { ord($_) } split(//, $unicode);
        print $metrics_fh encode_json({ codepoints => \@codepoints }) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };

close($metrics_fh);
exit 0;
