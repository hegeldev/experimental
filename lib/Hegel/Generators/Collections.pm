package Hegel::Generators::Collections;
use strict;
use warnings;

use Hegel::Generator;
use Hegel::TestCase;

use Exporter 'import';
our @EXPORT_OK = qw(
    lists tuples hashmaps one_of optional fixed_dictionaries
);

# --- Lists ---

sub lists {
    my ($elements, %args) = @_;
    my $min_size = $args{min_size} || 0;
    my $max_size = $args{max_size};

    my $basic = $elements->as_basic();
    if ($basic) {
        # Schema composition path
        my $schema = {
            type     => 'list',
            elements => $basic->schema(),
            min_size => $min_size,
        };
        $schema->{max_size} = $max_size if defined $max_size;

        my $elem_transform = $basic->{transform};
        my $transform;
        if ($elem_transform) {
            $transform = sub {
                my ($raw_list) = @_;
                return [ map { $elem_transform->($_) } @$raw_list ];
            };
        }
        return Hegel::BasicGenerator->new(
            schema    => $schema,
            transform => $transform,
        );
    }

    # Compositional fallback
    return _ListComposite->new(
        elements => $elements,
        min_size => $min_size,
        max_size => $max_size,
    );
}

package _ListComposite {
    use parent -norequire, 'Hegel::Generator';
    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub do_draw {
        my ($self, $tc) = @_;
        $tc->start_span(Hegel::TestCase::LABEL_LIST);
        my $coll_id = $tc->new_collection($self->{min_size}, $self->{max_size});
        my @result;
        while ($tc->collection_more($coll_id)) {
            $tc->start_span(Hegel::TestCase::LABEL_LIST_ELEMENT);
            push @result, $self->{elements}->do_draw($tc);
            $tc->stop_span(0);
        }
        $tc->stop_span(0);
        return \@result;
    }
}

package Hegel::Generators::Collections;

# --- Tuples ---

sub tuples {
    my @generators = @_;

    # Check if all elements are basic
    my @basics = map { $_->as_basic() } @generators;
    my $all_basic = !grep { !defined $_ } @basics;

    if ($all_basic) {
        my @schemas = map { $_->schema() } @basics;
        my $schema = {
            type     => 'tuple',
            elements => \@schemas,
        };

        my $has_transforms = grep { $_->{transform} } @basics;
        my $transform;
        if ($has_transforms) {
            my @transforms = map { $_->{transform} } @basics;
            $transform = sub {
                my ($raw_tuple) = @_;
                return [ map {
                    $transforms[$_] ? $transforms[$_]->($raw_tuple->[$_]) : $raw_tuple->[$_]
                } 0 .. $#transforms ];
            };
        }
        return Hegel::BasicGenerator->new(
            schema    => $schema,
            transform => $transform,
        );
    }

    # Compositional fallback
    return _TupleComposite->new(generators => \@generators);
}

package _TupleComposite {
    use parent -norequire, 'Hegel::Generator';
    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub do_draw {
        my ($self, $tc) = @_;
        $tc->start_span(Hegel::TestCase::LABEL_TUPLE);
        my @result;
        for my $gen (@{$self->{generators}}) {
            push @result, $gen->do_draw($tc);
        }
        $tc->stop_span(0);
        return \@result;
    }
}

package Hegel::Generators::Collections;

# --- Hashmaps (dicts) ---

sub hashmaps {
    my ($keys, $values, %args) = @_;
    my $min_size = $args{min_size} || 0;
    my $max_size = $args{max_size};

    my $basic_keys   = $keys->as_basic();
    my $basic_values = $values->as_basic();

    if ($basic_keys && $basic_values) {
        my $schema = {
            type     => 'dict',
            keys     => $basic_keys->schema(),
            values   => $basic_values->schema(),
            min_size => $min_size,
        };
        $schema->{max_size} = $max_size if defined $max_size;

        my $key_transform = $basic_keys->{transform};
        my $val_transform = $basic_values->{transform};

        # Dict always needs a transform to convert [[k,v], ...] pairs to hash
        my $transform = sub {
            my ($raw_pairs) = @_;
            my %result;
            for my $pair (@$raw_pairs) {
                my $k = $key_transform ? $key_transform->($pair->[0]) : $pair->[0];
                my $v = $val_transform ? $val_transform->($pair->[1]) : $pair->[1];
                $result{$k} = $v;
            }
            return \%result;
        };
        return Hegel::BasicGenerator->new(
            schema    => $schema,
            transform => $transform,
        );
    }

    # Compositional fallback
    return _DictComposite->new(
        keys     => $keys,
        values   => $values,
        min_size => $min_size,
        max_size => $max_size,
    );
}

package _DictComposite {
    use parent -norequire, 'Hegel::Generator';
    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub do_draw {
        my ($self, $tc) = @_;
        $tc->start_span(Hegel::TestCase::LABEL_MAP);
        my $coll_id = $tc->new_collection($self->{min_size}, $self->{max_size});
        my %result;
        while ($tc->collection_more($coll_id)) {
            $tc->start_span(Hegel::TestCase::LABEL_MAP_ENTRY);
            my $k = $self->{keys}->do_draw($tc);
            my $v = $self->{values}->do_draw($tc);
            # Silently overwrite duplicate keys (don't reject/loop)
            $result{$k} = $v;
            $tc->stop_span(0);
        }
        $tc->stop_span(0);
        return \%result;
    }
}

package Hegel::Generators::Collections;

# --- one_of ---

sub one_of {
    my @generators = @_;

    my @basics = map { $_->as_basic() } @generators;
    my $all_basic = !grep { !defined $_ } @basics;

    if ($all_basic) {
        my $has_transforms = grep { $_->{transform} } @basics;

        if (!$has_transforms) {
            # Simple case: all basic with no transforms
            my @schemas = map { $_->schema() } @basics;
            return Hegel::BasicGenerator->new(
                schema => { one_of => \@schemas },
            );
        }

        # Tagged tuple approach: each branch becomes [tag, value]
        my @branch_schemas;
        for my $i (0 .. $#basics) {
            push @branch_schemas, {
                type     => 'tuple',
                elements => [{ constant => $i }, $basics[$i]->schema()],
            };
        }
        return Hegel::BasicGenerator->new(
            schema    => { one_of => \@branch_schemas },
            transform => sub {
                my ($raw) = @_;
                my ($tag, $value) = @$raw;
                my $branch_transform = $basics[$tag]->{transform};
                return $branch_transform ? $branch_transform->($value) : $value;
            },
        );
    }

    # Compositional fallback
    return _OneOfComposite->new(generators => \@generators);
}

package _OneOfComposite {
    use parent -norequire, 'Hegel::Generator';
    use Hegel::Generators::Primitives qw(integers);
    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub do_draw {
        my ($self, $tc) = @_;
        my $gens = $self->{generators};
        $tc->start_span(Hegel::TestCase::LABEL_ONE_OF);
        my $idx = $tc->generate({ type => 'integer', min_value => 0, max_value => $#$gens });
        my $result = $gens->[$idx]->do_draw($tc);
        $tc->stop_span(0);
        return $result;
    }
}

package Hegel::Generators::Collections;

# --- optional ---

sub optional {
    my ($element) = @_;
    return one_of(Hegel::Generators::Primitives::just(undef), $element);
}

# --- fixed_dictionaries ---

sub fixed_dictionaries {
    my ($spec) = @_;
    # $spec is a hashref of { key => generator, ... }
    my @keys = sort keys %$spec;
    my @gens = map { $spec->{$_} } @keys;

    my $tuple_gen = tuples(@gens);
    return $tuple_gen->map(sub {
        my ($vals) = @_;
        my %result;
        for my $i (0 .. $#keys) {
            $result{$keys[$i]} = $vals->[$i];
        }
        return \%result;
    });
}

1;
