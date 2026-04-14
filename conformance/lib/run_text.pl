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
        # Report codepoints as an array of integers.
        # The server may send WTF-8 (surrogates), so decode manually:
        # parse UTF-8/WTF-8 byte sequences into codepoints.
        my @codepoints;
        my $i = 0;
        my @bytes = unpack("C*", $val);
        while ($i < scalar @bytes) {
            my $b = $bytes[$i];
            my ($cp, $len);
            if ($b < 0x80) {
                $cp = $b; $len = 1;
            } elsif ($b < 0xC0) {
                $cp = 0xFFFD; $len = 1;  # invalid continuation
            } elsif ($b < 0xE0) {
                $cp = ($b & 0x1F) << 6 | ($bytes[$i+1] & 0x3F); $len = 2;
            } elsif ($b < 0xF0) {
                $cp = ($b & 0x0F) << 12 | ($bytes[$i+1] & 0x3F) << 6 | ($bytes[$i+2] & 0x3F); $len = 3;
            } else {
                $cp = ($b & 0x07) << 18 | ($bytes[$i+1] & 0x3F) << 12 | ($bytes[$i+2] & 0x3F) << 6 | ($bytes[$i+3] & 0x3F); $len = 4;
            }
            push @codepoints, $cp;
            $i += $len;
        }
        print $metrics_fh encode_json({ codepoints => \@codepoints }) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };

close($metrics_fh);
exit 0;
