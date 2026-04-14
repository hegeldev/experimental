> [!NOTE]
> This is a Claude-authored implementation, created as a test of the
> [Hegel implementation guide](https://github.com/hegeldev/hegel-book).
> It is functional but has not been reviewed for production use.

> [!IMPORTANT]
> Hegel is in beta. As part of our beta, we may make breaking changes.
> See https://hegel.dev/compatibility for more details.

# Hegel for Perl

* [Website](https://hegel.dev)
* [Hegel implementation guide](https://github.com/hegeldev/hegel-book)

`hegel-perl` is a property-based testing library for Perl. It is based on [Hypothesis](https://github.com/hypothesisworks/hypothesis), using the [Hegel](https://hegel.dev/) protocol.

## Installation

### Prerequisites

- Perl 5.26+
- [uv](https://docs.astral.sh/uv/) (for installing the hegel-core server)
- CPAN modules: `CBOR::XS`, `JSON::XS`, `String::CRC32`, `Types::Serialiser`

Install dependencies:

```bash
cpanm CBOR::XS JSON::XS String::CRC32
```

Hegel will use `uv` to install the required [hegel-core](https://github.com/hegeldev/hegel-core) server component automatically on first test run.

## Quick Start

```perl
use Test::More;
use Hegel qw(hegel integers);

hegel "addition is commutative" => sub {
    my ($tc) = @_;
    my $x = $tc->draw(integers(min_value => -100, max_value => 100));
    my $y = $tc->draw(integers(min_value => -100, max_value => 100));
    is($x + $y, $y + $x, "x + y == y + x");
}, test_cases => 100;

done_testing;
```

Run with `prove`:

```bash
prove -I lib t/
```

## Finding Bugs

Here's a test that will find a bug in a sort function:

```perl
use Test::More;
use Hegel qw(hegel integers lists);

sub my_sort {
    my @sorted = sort { $a <=> $b } @{$_[0]};
    # Bug: accidentally removing duplicates
    my %seen;
    return [ grep { !$seen{$_}++ } @sorted ];
}

hegel "sort preserves length" => sub {
    my ($tc) = @_;
    my $list = $tc->draw(lists(integers(min_value => -100, max_value => 100),
                               min_size => 0, max_size => 20));
    my $sorted = my_sort($list);
    is(scalar @$sorted, scalar @$list, "length preserved");
};

done_testing;
```

Hegel will find a minimal failing example like `[0, 0]` -- a two-element list where both elements are the same, showing that our sort incorrectly removes duplicates.

## Features

### Generators

| Generator | Description |
|-----------|-------------|
| `integers(min_value => N, max_value => N)` | Integer values |
| `floats(min_value => N, max_value => N, ...)` | Floating point values |
| `booleans()` | Boolean values |
| `text(min_size => N, max_size => N)` | Unicode text |
| `binary(min_size => N, max_size => N)` | Binary data |
| `just($value)` | Constant value |
| `sampled_from([$a, $b, $c])` | Uniform choice from list |
| `from_regex($pattern)` | Strings matching a regex |

### Collections

| Generator | Description |
|-----------|-------------|
| `lists($gen, min_size => N, max_size => N)` | Lists of values |
| `tuples($gen1, $gen2, ...)` | Fixed-size tuples |
| `hashmaps($keys, $values, min_size => N, ...)` | Hash maps |
| `fixed_dictionaries({key => $gen, ...})` | Struct-like records |

### Combinators

| Combinator | Description |
|------------|-------------|
| `$gen->map(sub { ... })` | Transform values (preserves basicness) |
| `$gen->filter(sub { ... })` | Filter values |
| `$gen->flat_map(sub { ... })` | Dependent generation |
| `one_of($gen1, $gen2, ...)` | Choose from generators |
| `optional($gen)` | Value or undef |

### Format Generators

`emails()`, `urls()`, `domains()`, `ip_addresses()`, `dates()`, `times()`, `datetimes()`

### Control Functions

- `$tc->assume($condition)` -- Skip test case if condition is false
- `$tc->note($message)` -- Debug output shown on failure
- `$tc->target($value, $label)` -- Guide search toward interesting values

## Settings

```perl
hegel "my test" => sub { ... },
    test_cases => 200,    # Number of test cases (default: 100)
    seed => 42,           # Fixed random seed
    derandomize => 1;     # Derive seed from test name
```

## Requirements

- Perl 5.26+
- uv (installed automatically or available on PATH)
- Internet connection (for first-time hegel-core installation)

## License

This project is licensed under the Mozilla Public License 2.0.
