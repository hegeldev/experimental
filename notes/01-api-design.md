# API Design Decisions for hegel-perl

## Decision 1: Test Entry Point

Perl tests use `Test::More` and the `prove` runner. Tests live in `t/` as `.t` files.
The natural integration is a `hegel` function that works like `subtest` - it runs the
test body, integrates with TAP output, and handles the engine lifecycle.

**Choice:** `hegel($name, $body, %settings)` function that produces TAP output via Test::More.

## Decision 2: Drawing Values

**Choice:** Explicit context passing. `$tc->draw($gen)` where `$tc` is passed to the
test body. Perl developers are used to explicit parameter passing, and this avoids
any issues with global state.

## Decision 3: Generator Construction

Perl has hash-based named arguments, so generators use functions with optional named params:
`integers(min_value => 0, max_value => 100)`. This is the most natural Perl idiom.

**Choice:** Named argument functions that return generator objects.

## Decision 4: Control Functions

- `$tc->assume($condition)` - dies with a Hegel::UnsatisfiedAssumption object
- `$tc->note($message)` - records debug output for final replay
- `$tc->target($value, $label)` - guides search

## Decision 5: Settings

Settings passed as trailing hash pairs to `hegel()`:
`hegel("name", sub { ... }, test_cases => 500, seed => 42)`

## Decision 6: Generator Type

Generators are blessed objects implementing:
- `generate($tc)` / `do_draw($tc)` - produce a value
- `as_basic()` - return BasicGenerator or undef
- `map($f)` - preserves basicness when source is basic
- `filter($pred)` - always composite
- `flat_map($f)` - always composite

BasicGenerator is a subclass with schema + optional transform.

## Protocol Note

There is a discrepancy in the docs: `architecture.md` says stdin/stdout pipes,
`library-api.md` says Unix domain sockets. Looking at actual implementations:
- hegel-rust and hegel-typescript both use `--stdio` flag and pipe to subprocess
- The TypeScript handshake sends "hegel_handshake_start" over stdin
- So **stdio pipes** is the actual mechanism, not Unix sockets

RESOLVED: hegel-core supports both Unix sockets (default) and stdio mode (--stdio flag).
Both hegel-rust and hegel-typescript use `--stdio` mode. We will use `--stdio` for
hegel-perl since it's simpler - no socket path management needed.

The server command is: `uv tool run --from hegel-core==0.4.0 hegel --stdio --verbosity normal`

Handshake: Send raw bytes "hegel_handshake_start" as packet payload on stream 0.
Receive "Hegel/0.10" as reply. Parse version, validate it's supported.

BOOK NOTE: The architecture.md chapter correctly describes stdin/stdout pipes. The
library-api.md spec says "Unix domain sockets" which is the DEFAULT mode but not what
the newer implementations use. The spec should mention --stdio mode, or at least
note that both transports exist.
