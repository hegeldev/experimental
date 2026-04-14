package Hegel::Generators::Primitives;
use strict;
use warnings;

use Hegel::Generator;

use Exporter 'import';
our @EXPORT_OK = qw(
    integers floats booleans text binary characters
    just sampled_from from_regex
    emails urls domains ip_addresses dates times datetimes
);

# --- Primitive generators ---

sub integers {
    my (%args) = @_;
    my $schema = { type => 'integer' };
    $schema->{min_value} = $args{min_value} if defined $args{min_value};
    $schema->{max_value} = $args{max_value} if defined $args{max_value};
    return Hegel::BasicGenerator->new(schema => $schema);
}

sub floats {
    my (%args) = @_;
    my $schema = { type => 'float' };
    $schema->{min_value}      = $args{min_value} + 0.0      if defined $args{min_value};
    $schema->{max_value}      = $args{max_value} + 0.0      if defined $args{max_value};
    $schema->{allow_nan}      = $args{allow_nan} ? \1 : \0  if defined $args{allow_nan};
    $schema->{allow_infinity} = $args{allow_infinity} ? \1 : \0 if defined $args{allow_infinity};
    $schema->{exclude_min}    = $args{exclude_min} ? \1 : \0 if defined $args{exclude_min};
    $schema->{exclude_max}    = $args{exclude_max} ? \1 : \0 if defined $args{exclude_max};
    $schema->{width}          = $args{width}                 if defined $args{width};
    return Hegel::BasicGenerator->new(schema => $schema);
}

sub booleans {
    return Hegel::BasicGenerator->new(schema => { type => 'boolean' });
}

sub text {
    my (%args) = @_;
    my $schema = { type => 'string', min_size => $args{min_size} || 0 };
    $schema->{max_size}            = $args{max_size}            if defined $args{max_size};
    $schema->{codec}               = $args{codec}               if defined $args{codec};
    $schema->{min_codepoint}       = $args{min_codepoint}       if defined $args{min_codepoint};
    $schema->{max_codepoint}       = $args{max_codepoint}       if defined $args{max_codepoint};
    $schema->{categories}          = $args{categories}          if defined $args{categories};
    $schema->{exclude_categories}  = $args{exclude_categories}  if defined $args{exclude_categories};
    $schema->{include_characters}  = $args{include_characters}  if defined $args{include_characters};
    $schema->{exclude_characters}  = $args{exclude_characters}  if defined $args{exclude_characters};
    return Hegel::BasicGenerator->new(schema => $schema);
}

sub characters {
    my (%args) = @_;
    $args{min_size} = 1;
    $args{max_size} = 1;
    return text(%args);
}

sub binary {
    my (%args) = @_;
    my $schema = { type => 'binary', min_size => $args{min_size} || 0 };
    $schema->{max_size} = $args{max_size} if defined $args{max_size};
    return Hegel::BasicGenerator->new(schema => $schema);
}

sub just {
    my ($value) = @_;
    return Hegel::BasicGenerator->new(
        schema    => { constant => undef },
        transform => sub { $value },
    );
}

sub sampled_from {
    my ($values) = @_;
    my @vals = @$values;
    my $len = scalar @vals;
    Carp::croak("sampled_from requires a non-empty list") unless $len > 0;
    return Hegel::BasicGenerator->new(
        schema    => { type => 'integer', min_value => 0, max_value => $len - 1 },
        transform => sub { $vals[$_[0]] },
    );
}

sub from_regex {
    my ($pattern, %args) = @_;
    my $schema = { type => 'regex', pattern => $pattern };
    $schema->{fullmatch} = $args{fullmatch} ? \1 : \0 if defined $args{fullmatch};
    if ($args{alphabet}) {
        $schema->{alphabet} = $args{alphabet};
    }
    return Hegel::BasicGenerator->new(schema => $schema);
}

# --- Format generators ---

sub emails    { Hegel::BasicGenerator->new(schema => { type => 'email' }) }
sub urls      { Hegel::BasicGenerator->new(schema => { type => 'url' }) }

sub domains {
    my (%args) = @_;
    my $schema = { type => 'domain' };
    $schema->{max_length} = $args{max_length} if defined $args{max_length};
    return Hegel::BasicGenerator->new(schema => $schema);
}

sub ip_addresses {
    my (%args) = @_;
    my $version = $args{version};
    if (!defined $version || $version eq 'both') {
        return Hegel::BasicGenerator->new(
            schema => { one_of => [{ type => 'ipv4' }, { type => 'ipv6' }] }
        );
    }
    if ($version == 4) {
        return Hegel::BasicGenerator->new(schema => { type => 'ipv4' });
    }
    if ($version == 6) {
        return Hegel::BasicGenerator->new(schema => { type => 'ipv6' });
    }
    Carp::croak("ip_addresses: version must be 4, 6, or 'both'");
}

sub dates     { Hegel::BasicGenerator->new(schema => { type => 'date' }) }
sub times     { Hegel::BasicGenerator->new(schema => { type => 'time' }) }
sub datetimes { Hegel::BasicGenerator->new(schema => { type => 'datetime' }) }

1;
