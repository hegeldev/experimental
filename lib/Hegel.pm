package Hegel;
use strict;
use warnings;

use Hegel::Runner;
use Hegel::Generator;
use Hegel::Generators::Primitives;
use Hegel::Generators::Collections;
use Test::More ();

use Exporter 'import';
our @EXPORT_OK = qw(
    hegel
    integers floats booleans text binary characters
    just sampled_from from_regex
    lists tuples hashmaps one_of optional fixed_dictionaries
    emails urls domains ip_addresses dates times datetimes
);

our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

# Re-export generator constructors
*integers       = \&Hegel::Generators::Primitives::integers;
*floats         = \&Hegel::Generators::Primitives::floats;
*booleans       = \&Hegel::Generators::Primitives::booleans;
*text           = \&Hegel::Generators::Primitives::text;
*binary         = \&Hegel::Generators::Primitives::binary;
*characters     = \&Hegel::Generators::Primitives::characters;
*just           = \&Hegel::Generators::Primitives::just;
*sampled_from   = \&Hegel::Generators::Primitives::sampled_from;
*from_regex     = \&Hegel::Generators::Primitives::from_regex;
*emails         = \&Hegel::Generators::Primitives::emails;
*urls           = \&Hegel::Generators::Primitives::urls;
*domains        = \&Hegel::Generators::Primitives::domains;
*ip_addresses   = \&Hegel::Generators::Primitives::ip_addresses;
*dates          = \&Hegel::Generators::Primitives::dates;
*times          = \&Hegel::Generators::Primitives::times;
*datetimes      = \&Hegel::Generators::Primitives::datetimes;
*lists          = \&Hegel::Generators::Collections::lists;
*tuples         = \&Hegel::Generators::Collections::tuples;
*hashmaps       = \&Hegel::Generators::Collections::hashmaps;
*one_of         = \&Hegel::Generators::Collections::one_of;
*optional       = \&Hegel::Generators::Collections::optional;
*fixed_dictionaries = \&Hegel::Generators::Collections::fixed_dictionaries;

# Main test entry point
# Usage: hegel "test name" => sub { my ($tc) = @_; ... }, %settings;
sub hegel {
    my ($name, $test_fn, %settings) = @_;

    my $runner = Hegel::Runner->new(
        test_fn  => $test_fn,
        settings => \%settings,
    );

    Test::More::subtest($name => sub {
        my $result = $runner->run();

        if ($result->{error_message}) {
            Test::More::fail("Hegel error: $result->{error_message}");
        } elsif ($result->{failure_message}) {
            Test::More::fail("Falsifying example found:\n$result->{failure_message}");
        } elsif ($result->{passed}) {
            Test::More::pass("Property held for all test cases");
        }
    });
}

1;
