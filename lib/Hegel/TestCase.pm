package Hegel::TestCase;
use strict;
use warnings;

use Carp qw(croak);

# Exception class for assume() failures
package Hegel::UnsatisfiedAssumption {
    sub new { bless {}, $_[0] }
    sub throw { die $_[0]->new() }
}

# Exception class for StopTest from server
package Hegel::StopTest {
    sub new { bless { message => $_[1] || 'StopTest' }, $_[0] }
    sub throw { die $_[0]->new($_[1]) }
    sub message { $_[0]->{message} }
}

package Hegel::TestCase;

# Span labels
use constant {
    LABEL_LIST         => 1,
    LABEL_LIST_ELEMENT => 2,
    LABEL_SET          => 3,
    LABEL_SET_ELEMENT  => 4,
    LABEL_MAP          => 5,
    LABEL_MAP_ENTRY    => 6,
    LABEL_TUPLE        => 7,
    LABEL_ONE_OF       => 8,
    LABEL_OPTIONAL     => 9,
    LABEL_FIXED_DICT   => 10,
    LABEL_FLAT_MAP     => 11,
    LABEL_FILTER       => 12,
    LABEL_MAPPED       => 13,
    LABEL_SAMPLED_FROM => 14,
    LABEL_ENUM_VARIANT => 15,
};

sub new {
    my ($class, %args) = @_;
    return bless {
        data_source => $args{data_source},
        is_final    => $args{is_final} || 0,
        span_depth  => 0,
        notes       => [],
        draws       => [],
    }, $class;
}

sub is_final   { $_[0]->{is_final} }
sub is_aborted { $_[0]->{data_source}->test_aborted() }

# Draw a value from a generator
sub draw {
    my ($self, $generator, $label) = @_;
    croak "TestCase is aborted" if $self->is_aborted;

    my $value = $generator->do_draw($self);

    if ($self->{span_depth} == 0 && $self->{is_final}) {
        $label //= 'draw';
        push @{$self->{draws}}, { label => $label, value => $value };
    }

    return $value;
}

# Reject the current test case
sub assume {
    my ($self, $condition) = @_;
    return if $condition;
    Hegel::UnsatisfiedAssumption->throw();
}

# Record a note (displayed on final run only)
sub note {
    my ($self, $message) = @_;
    push @{$self->{notes}}, $message;
}

# Guide the search engine
sub target {
    my ($self, $value, $label) = @_;
    $label //= 'target';
    $self->{data_source}->target($value, $label);
}

# --- Delegate to DataSource ---

sub generate {
    my ($self, $schema) = @_;
    return $self->{data_source}->generate($schema);
}

sub start_span {
    my ($self, $label) = @_;
    $self->{span_depth}++;
    $self->{data_source}->start_span($label);
}

sub stop_span {
    my ($self, $discard) = @_;
    $self->{span_depth}-- if $self->{span_depth} > 0;
    $self->{data_source}->stop_span($discard);
}

sub mark_complete {
    my ($self, $status, $origin) = @_;
    $self->{data_source}->mark_complete($status, $origin);
}

sub new_collection {
    my ($self, $min_size, $max_size) = @_;
    return $self->{data_source}->new_collection($min_size, $max_size);
}

sub collection_more {
    my ($self, $collection_id) = @_;
    return $self->{data_source}->collection_more($collection_id);
}

sub collection_reject {
    my ($self, $collection_id, $why) = @_;
    $self->{data_source}->collection_reject($collection_id, $why);
}

# Print notes (on final run)
sub print_notes {
    my ($self) = @_;
    return unless $self->{is_final} && @{$self->{notes}};
    for my $note (@{$self->{notes}}) {
        print STDERR "Note: $note\n";
    }
}

# Print draws (on final run)
sub print_draws {
    my ($self) = @_;
    return unless $self->{is_final} && @{$self->{draws}};
    for my $draw (@{$self->{draws}}) {
        my $val = $draw->{value};
        my $str = ref $val ? _dump_value($val) : (defined $val ? "$val" : 'undef');
        print STDERR "  $draw->{label} = $str\n";
    }
}

sub _dump_value {
    my ($val) = @_;
    if (ref $val eq 'ARRAY') {
        return '[' . join(', ', map { ref $_ ? _dump_value($_) : (defined $_ ? $_ : 'undef') } @$val) . ']';
    }
    if (ref $val eq 'HASH') {
        return '{' . join(', ', map { "$_ => " . (defined $val->{$_} ? (ref $val->{$_} ? _dump_value($val->{$_}) : $val->{$_}) : 'undef') } sort keys %$val) . '}';
    }
    return "$val";
}

1;
