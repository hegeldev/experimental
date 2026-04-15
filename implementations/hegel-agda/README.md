> [!IMPORTANT]
>
> This library was written entirely by an AI agent (Claude) running under a custom development
> harness, with minimal to no human supervision during its creation. We expect it probably works,
> but it may in fact be extremely bad in ways we would not know about, because we have not
> meaningfully reviewed it. Please treat it with appropriate scepticism and caution.

> [!NOTE]
> This is a Claude-written implementation of a Hegel library for Agda.
> It was created as an experiment in bringing property-based testing to
> a dependently-typed proof assistant. The implementation is functional
> but early-stage.

> [!IMPORTANT]
> Hegel is in beta and may make breaking changes. See https://hegel.dev/compatibility for details.

# Hegel for Agda

* [Hegel website](https://hegel.dev)
* [hegel-core](https://github.com/hegeldev/hegel-core) (the server component)

`hegel-agda` is a property-based testing library for Agda. It is based on [Hypothesis](https://github.com/hypothesisworks/hypothesis), using the [Hegel](https://hegel.dev/) protocol.

Agda is a dependently-typed programming language and proof assistant. `hegel-agda` brings Hypothesis-quality property-based testing to Agda programs, including automatic shrinking of counterexamples to minimal reproductions.

## Architecture

`hegel-agda` uses Agda's GHC backend to compile to Haskell. The protocol layer (CBOR encoding, wire format, connection management) is implemented in Haskell and exposed to Agda via `FOREIGN GHC` pragmas and postulates.

```
┌───────────────────┐     ┌───────────────────┐
│   Agda test code  │     │                   │
│   (generators,    │────▶│   hegel-core      │
│    assertions)    │     │   (Python/        │
│         │         │◀────│    Hypothesis)    │
│    ┌────┴────┐    │     │                   │
│    │ Haskell │    │     └───────────────────┘
│    │   FFI   │    │       stdin/stdout
│    └─────────┘    │       binary protocol
└───────────────────┘
```

## Prerequisites

- [Agda](https://agda.readthedocs.io/) 2.7.0+ with the GHC backend
- [GHC](https://www.haskell.org/ghc/) 9.6+
- [Haskell packages](https://hackage.haskell.org/): `cborg`, `digest`, `text`, `containers`, `process`, `bytestring`
- [Python](https://python.org/) 3.10+ with [hegel-core](https://pypi.org/project/hegel-core/) installed
- [`uv`](https://docs.astral.sh/uv/) (recommended, for managing hegel-core)

## Install Hegel for Agda

1. Install Agda and GHC (e.g. via [ghcup](https://www.haskell.org/ghcup/))
2. Install the Haskell dependencies:
   ```
   cabal install --lib cborg serialise digest text containers process bytestring
   ```
3. Install hegel-core:
   ```
   pip install hegel-core
   ```
4. Clone this repository and register the library:
   ```
   echo "/path/to/hegel-agda/hegel-agda.agda-lib" >> ~/.agda/libraries
   ```

## Write your first test

Create a new file `MyTest.agda`:

```agda
module MyTest where

open import Data.Bool.Base using (Bool; true)
open import Data.Integer.Base using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)
open import Hegel

testIntegerSelfEquality : TestCase → Prim.IO ⊤
testIntegerSelfEquality tc =
  draw tc integers Prim.>>= λ n →
  -- Integers should always be equal to themselves.
  -- This test always passes.
  Prim.pure tt

main : Prim.IO ⊤
main =
  runHegelTests
    ( pair "integer self-equality" testIntegerSelfEquality
    ∷ [])
  Prim.>>= λ _ → Prim.pure tt
```

Compile and run it:

```bash
agda --compile \
  --ghc-flag="-i hs-support" \
  --ghc-flag="-package-env .ghc.environment.<arch>-linux-<ghc-version>" \
  --compile-dir=build \
  MyTest.agda

./build/MyTest
```

You should see `PASS: integer self-equality`.

Here's what's happening: `runHegelTests` runs each test function many times (100 by default). The test function takes a `TestCase` parameter, which provides access to `draw` for generating random values. This test draws a random integer and does nothing with it — so it always passes.

Now try a test that fails. Use `assume` to assert a property — when the property is false, Hegel reports a counterexample:

```agda
open import Data.Integer.Base using (_≤ᵇ_)

testIntegersAlwaysSmall : TestCase → Prim.IO ⊤
testIntegersAlwaysSmall tc =
  draw tc integers Prim.>>= λ n →
  -- This will fail! Not all integers are ≤ 50.
  assume tc (n ≤ᵇ + 50) Prim.>>= λ _ →
  Prim.pure tt
```

Hegel will find a counterexample (an integer > 50) and then **shrink** it to find the smallest one — in this case, `51`.

To fix this, constrain the generated integers:

```agda
testBoundedIntegers : TestCase → Prim.IO ⊤
testBoundedIntegers tc =
  draw tc (integersIn (+ 0) (+ 50)) Prim.>>= λ n →
  assume tc (n ≤ᵇ + 50) Prim.>>= λ _ →
  Prim.pure tt
```

Now the test passes because `integersIn` constrains the generated values to the range [0, 50].

## Use generators

Hegel provides a rich set of generators out of the box.

### Primitive generators

| Generator | Type | Description |
|-----------|------|-------------|
| `integers` | `Generator ℤ` | Unbounded integers |
| `integersIn lo hi` | `Generator ℤ` | Integers in [lo, hi] |
| `floats` | `Generator Float` | Floating-point numbers |
| `booleans` | `Generator Bool` | `true` or `false` |
| `text` | `Generator String` | Unicode strings |
| `binary` | `Generator ByteString` | Raw byte sequences |

### Collection generators

Use `lists` to generate lists from an element generator:

```agda
open import Data.List.Base using (length; _++_)
open import Data.Nat.Base using (_≤ᵇ_)

testAppendIncreasesLength : TestCase → Prim.IO ⊤
testAppendIncreasesLength tc =
  draw tc (lists (integersIn (+ 0) (+ 100))) Prim.>>= λ xs →
  draw tc (integersIn (+ 0) (+ 100)) Prim.>>= λ n →
  let ys = xs ++ (n ∷ []) in
  assume tc (length xs Data.Nat.Base.≤ᵇ length ys) Prim.>>= λ _ →
  Prim.pure tt
```

Other collection generators:

| Generator | Type | Description |
|-----------|------|-------------|
| `lists gen` | `Generator (List A)` | Lists of values from `gen` |
| `listsWith opts gen` | `Generator (List A)` | Lists with size constraints |
| `tuples genA genB` | `Generator (A × B)` | Pairs of values |
| `dicts keyGen valGen` | `Generator (List (K × V))` | Key-value pair lists |
| `sampledFrom vals` | `Generator A` | Uniform choice from a list |

### Combinators

Combinators transform generators into new generators:

```agda
-- map: transform generated values (preserves basicness for efficient generation)
evenInts : Generator ℤ
evenInts = gmap (ℤ._*_ (+ 2)) (integersIn (+ 0) (+ 50))

-- filter: restrict generated values (use sparingly — prefer constraints)
positiveInts : Generator ℤ
positiveInts = gfilter isPositive (integersIn (+ 0) (+ 100))
  where
    isPositive : ℤ → Bool
    isPositive (+ zero)    = false
    isPositive (+ (suc _)) = true
    isPositive _           = false

-- oneOf: choose between multiple generators
intOrBool : Generator ℤ
intOrBool = oneOf
  ( integersIn (+ 0) (+ 10)
  ∷ integersIn (+ 90) (+ 100)
  ∷ [])

-- optional: generate Nothing or Just
maybeName : Generator (Maybe String)
maybeName = optional text
```

### Custom composite generators

Use `composite` to build generators that depend on previously drawn values:

```agda
open import Data.Product.Base using (_×_; _,_)

-- Generate a pair where the second element depends on the first
generateRange : Generator (ℤ × ℤ)
generateRange = composite λ tc →
  draw tc (integersIn (+ 0) (+ 100)) Prim.>>= λ lo →
  draw tc (integersIn lo (+ 100)) Prim.>>= λ hi →
  Prim.pure (lo , hi)
```

This is useful when the shape of one generated value depends on another — for example, generating a list and then an index into it, or generating a range and then a value within that range.

### Format generators

Generate structured strings matching common formats:

| Generator | Example output |
|-----------|----------------|
| `emails` | `"user@example.com"` |
| `urls` | `"https://example.org/path"` |
| `domains` | `"example.co.uk"` |
| `ipv4` | `"192.168.1.1"` |
| `ipv6` | `"::1"` |
| `dates` | `"2024-03-15"` |
| `times` | `"14:30:00"` |
| `datetimes` | `"2024-03-15T14:30:00"` |
| `fromRegex pat` | Strings matching a regex pattern |

## Debug your failing test cases

Use `note` to attach debug information to a test case. Notes only appear when Hegel replays the minimal failing example:

```agda
testWithNotes : TestCase → Prim.IO ⊤
testWithNotes tc =
  draw tc integers Prim.>>= λ x →
  draw tc integers Prim.>>= λ y →
  note tc ("x + y = ...") Prim.>>= λ _ →
  Prim.pure tt
```

## Change the number of test cases

By default, Hegel runs 100 test cases per test. To change this, use `runHegelTest` with a custom `Settings` value (via the Haskell FFI layer). The default can also be overridden by setting the `HEGEL_MAX_EXAMPLES` environment variable before running your test binary.

## Features

- **Hypothesis-quality shrinking**: Failing examples are automatically reduced to minimal reproductions
- **Persistent example database**: Failing examples are saved and replayed across runs
- **Coverage-guided generation**: Branch coverage guides the engine to explore new code paths
- **All Hegel generators**: integers, floats, booleans, text, binary, lists, tuples, dicts, one-of, format strings (emails, URLs, dates, etc.)
- **Control functions**: `assume` (reject test cases), `note` (debug output), `target` (guide search)

## Learning more

- Browse `src/Hegel/Generators/Primitives.agda` for all primitive generators and their options.
- Browse `src/Hegel/Combinators.agda` for combinators: `gmap`, `gfilter`, `flatMap`, `oneOf`, `optional`.
- Browse `src/Hegel/Generators/Collections.agda` for collection generators with full options.
- Browse `src/Hegel/Generators/Format.agda` for format string generators.
- See `test/TestGenerators.agda` and `test/TestComprehensive.agda` for working examples.

## License

MPL-2.0
