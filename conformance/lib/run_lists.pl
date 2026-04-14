use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);

use Types::Serialiser;
use Hegel::Runner;
use Hegel::Generator;
use Hegel::TestCase;
use Hegel::Generators::Primitives qw(integers);
use Hegel::Generators::Collections qw(lists);

my $params_json = $ARGV[0] || '{}';
my $params = decode_json($params_json);

my $metrics_file = $ENV{CONFORMANCE_METRICS_FILE} or die "CONFORMANCE_METRICS_FILE not set";
my $test_cases = ($ENV{CONFORMANCE_TEST_CASES} || 50) + 0;

open(my $metrics_fh, '>', $metrics_file) or die "Cannot open $metrics_file: $!";
$metrics_fh->autoflush(1);

my %int_args;
$int_args{min_value} = $params->{min_value} if defined $params->{min_value};
$int_args{max_value} = $params->{max_value} if defined $params->{max_value};

my $elem_gen = integers(%int_args);
my $unique = $params->{unique} ? 1 : 0;

# In non_basic mode, force the compositional path
my $mode = $params->{mode} || 'basic';
if ($mode eq 'non_basic') {
    $elem_gen = $elem_gen->filter(sub { 1 });
}

my %list_args;
$list_args{min_size} = ($params->{min_size} + 0) if defined $params->{min_size};
$list_args{max_size} = ($params->{max_size} + 0) if defined $params->{max_size};

my $gen;
if ($unique && $mode eq 'basic') {
    # Basic path with unique schema flag
    my $basic = integers(%int_args)->as_basic();
    my $schema = {
        type     => 'list',
        elements => $basic->schema(),
        min_size => $list_args{min_size} || 0,
        unique   => Types::Serialiser::true,
    };
    $schema->{max_size} = $list_args{max_size} if defined $list_args{max_size};
    $gen = Hegel::BasicGenerator->new(schema => $schema);
} elsif ($unique && $mode eq 'non_basic') {
    # Non-basic unique: use collection protocol with rejection
    $gen = _UniqueListGen->new(
        elements => $elem_gen,
        min_size => $list_args{min_size} || 0,
        max_size => $list_args{max_size},
    );
} else {
    $gen = lists($elem_gen, %list_args);
}

package _UniqueListGen {
    use parent -norequire, 'Hegel::Generator';
    sub new { bless { @_[1..$#_] }, $_[0] }
    sub do_draw {
        my ($self, $tc) = @_;
        $tc->start_span(Hegel::TestCase::LABEL_LIST);
        my $coll_id = $tc->new_collection($self->{min_size}, $self->{max_size});
        my @result;
        my %seen;
        while ($tc->collection_more($coll_id)) {
            $tc->start_span(Hegel::TestCase::LABEL_LIST_ELEMENT);
            my $val = $self->{elements}->do_draw($tc);
            if ($seen{$val}++) {
                $tc->collection_reject($coll_id, "duplicate");
                $tc->stop_span(1);
                next;
            }
            push @result, $val;
            $tc->stop_span(0);
        }
        $tc->stop_span(0);
        return \@result;
    }
}

package main;

my $runner = Hegel::Runner->new(
    test_fn => sub {
        my ($tc) = @_;
        my $val = $tc->draw($gen);
        # Force numeric context on integer elements for JSON encoding
        my @elements = map { $_ + 0 } @$val;
        print $metrics_fh encode_json({ elements => \@elements }) . "\n";
    },
    settings => { test_cases => $test_cases },
);

eval { $runner->run() };

close($metrics_fh);
exit 0;
