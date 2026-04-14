# Getting Started with Hegel for Perl

This guide walks you through writing your first property-based test with hegel-perl.

## What is Property-Based Testing?

Instead of testing specific input-output pairs, property-based testing generates random inputs and checks that invariants ("properties") hold for all of them. When a property fails, the framework automatically *shrinks* the input to find the smallest failing example.

## Setup

Install the required Perl modules:

```bash
cpanm CBOR::XS JSON::XS String::CRC32
```

Make sure [uv](https://docs.astral.sh/uv/) is installed (hegel-perl uses it to manage the test server):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Your First Test

Create a file `t/my_property.t`:

```perl
use strict;
use warnings;
use Test::More;
use Hegel qw(hegel integers);

hegel "addition is commutative" => sub {
    my ($tc) = @_;
    my $x = $tc->draw(integers(min_value => -1000, max_value => 1000));
    my $y = $tc->draw(integers(min_value => -1000, max_value => 1000));
    is($x + $y, $y + $x);
}, test_cases => 100;

done_testing;
```

Run it:

```bash
prove -I lib t/my_property.t
```

## How It Works

1. **`hegel "name" => sub { ... }`** declares a property-based test
2. **`$tc->draw($generator)`** draws a random value from a generator
3. **Test::More assertions** (`is`, `ok`, `cmp_ok`, etc.) check the property
4. If an assertion fails, Hegel *shrinks* the inputs to find the simplest counterexample

## Generators

Generators describe what kind of data to produce.

### Primitives

```perl
integers()                                    # any integer
integers(min_value => 0, max_value => 100)    # bounded
floats(min_value => 0.0, max_value => 1.0)    # bounded floats
booleans()                                     # true or false
text(min_size => 1, max_size => 50)           # Unicode strings
binary(min_size => 0, max_size => 100)        # raw bytes
```

### Collections

```perl
lists(integers(), min_size => 1, max_size => 10)   # lists of integers
tuples(integers(), text())                          # fixed-size pairs
hashmaps(text(), integers(), min_size => 0, max_size => 5)  # hash maps
```

### Combinators

```perl
# Transform values
integers(min_value => 0, max_value => 50)->map(sub { $_[0] * 2 })  # even numbers

# Filter values
integers(min_value => -100, max_value => 100)->filter(sub { $_[0] != 0 })  # non-zero

# Dependent generation
integers(min_value => 1, max_value => 5)->flat_map(sub {
    my $n = $_[0];
    lists(booleans(), min_size => $n, max_size => $n)
})

# Choice between generators
one_of(integers(), text())

# Optional values (undef or a value)
optional(integers(min_value => 1, max_value => 100))
```

## Control Functions

```perl
hegel "division" => sub {
    my ($tc) = @_;
    my $n = $tc->draw(integers());
    my $d = $tc->draw(integers());
    
    # Skip test cases where divisor is zero
    $tc->assume($d != 0);
    
    # Debug output (shown only for failing examples)
    $tc->note("n=$n, d=$d");
    
    # Guide the search toward interesting values
    $tc->target(abs($n) + 0.0, "magnitude");
    
    my $q = int($n / $d);
    is($q * $d + ($n % $d), $n, "quotient-remainder identity");
};
```

## Settings

Control test behavior with settings:

```perl
hegel "my test" => sub { ... },
    test_cases => 200,     # More test cases (default: 100)
    seed => 42,            # Reproducible randomness
    derandomize => 1;      # Derive seed from test name
```

## Tips

- **Prefer `map` over `filter`**: `integers(0, 50)->map(sub { $_[0] * 2 })` is better than `integers(0, 100)->filter(sub { $_[0] % 2 == 0 })` because it gives the engine better shrinking.
- **Use `assume` sparingly**: If you're rejecting more than 10% of test cases, consider restructuring your generators.
- **Start simple**: Begin with basic properties ("does it not crash?", "is the output the right type?") before testing complex invariants.
