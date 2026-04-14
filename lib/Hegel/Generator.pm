package Hegel::Generator;
use strict;
use warnings;

use Carp qw(croak);

# Base class for all generators.
# Subclasses must implement do_draw($tc).
# Optionally implement as_basic() to return a Hegel::BasicGenerator.

sub new {
    my ($class, %args) = @_;
    return bless { %args }, $class;
}

# Must be overridden by subclasses
sub do_draw {
    my ($self, $tc) = @_;
    croak ref($self) . "::do_draw not implemented";
}

# Return a BasicGenerator if this generator has a schema, undef otherwise.
sub as_basic {
    return undef;
}

# Combinators

sub map {
    my ($self, $fn) = @_;
    return Hegel::MappedGenerator->new(source => $self, fn => $fn);
}

sub filter {
    my ($self, $pred) = @_;
    return Hegel::FilteredGenerator->new(source => $self, predicate => $pred);
}

sub flat_map {
    my ($self, $fn) = @_;
    return Hegel::FlatMappedGenerator->new(source => $self, fn => $fn);
}

# --- BasicGenerator ---

package Hegel::BasicGenerator;
use parent -norequire, 'Hegel::Generator';
use Carp qw(croak);

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->{schema}    = $args{schema} || croak "BasicGenerator requires schema";
    $self->{transform} = $args{transform};  # optional: sub ($raw) -> $value
    return $self;
}

sub schema { $_[0]->{schema} }

sub as_basic { $_[0] }

sub do_draw {
    my ($self, $tc) = @_;
    my $raw = $tc->generate($self->{schema});
    if ($self->{transform}) {
        return $self->{transform}->($raw);
    }
    return $raw;
}

# map on a BasicGenerator produces a new BasicGenerator (preserves schema!)
sub map {
    my ($self, $fn) = @_;
    my $old_transform = $self->{transform};
    my $new_transform;
    if ($old_transform) {
        $new_transform = sub { $fn->($old_transform->($_[0])) };
    } else {
        $new_transform = $fn;
    }
    return Hegel::BasicGenerator->new(
        schema    => $self->{schema},
        transform => $new_transform,
    );
}

# --- MappedGenerator (non-basic) ---

package Hegel::MappedGenerator;
use parent -norequire, 'Hegel::Generator';

use Hegel::TestCase;

sub new {
    my ($class, %args) = @_;
    return bless {
        source => $args{source},
        fn     => $args{fn},
    }, $class;
}

sub do_draw {
    my ($self, $tc) = @_;
    $tc->start_span(Hegel::TestCase::LABEL_MAPPED);
    my $raw = $self->{source}->do_draw($tc);
    my $result = $self->{fn}->($raw);
    $tc->stop_span(0);
    return $result;
}

# --- FilteredGenerator ---

package Hegel::FilteredGenerator;
use parent -norequire, 'Hegel::Generator';

use Hegel::TestCase;

use constant MAX_FILTER_ATTEMPTS => 3;

sub new {
    my ($class, %args) = @_;
    return bless {
        source    => $args{source},
        predicate => $args{predicate},
    }, $class;
}

sub do_draw {
    my ($self, $tc) = @_;
    for my $attempt (1 .. MAX_FILTER_ATTEMPTS) {
        $tc->start_span(Hegel::TestCase::LABEL_FILTER);
        my $value = $self->{source}->do_draw($tc);
        if ($self->{predicate}->($value)) {
            $tc->stop_span(0);
            return $value;
        }
        $tc->stop_span(1);  # discard
    }
    $tc->assume(0);  # reject test case
}

# --- FlatMappedGenerator ---

package Hegel::FlatMappedGenerator;
use parent -norequire, 'Hegel::Generator';

use Hegel::TestCase;

sub new {
    my ($class, %args) = @_;
    return bless {
        source => $args{source},
        fn     => $args{fn},
    }, $class;
}

sub do_draw {
    my ($self, $tc) = @_;
    $tc->start_span(Hegel::TestCase::LABEL_FLAT_MAP);
    my $intermediate = $self->{source}->do_draw($tc);
    my $next_gen = $self->{fn}->($intermediate);
    my $result = $next_gen->do_draw($tc);
    $tc->stop_span(0);
    return $result;
}

1;
