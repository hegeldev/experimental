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

## Requirements

- [Agda](https://agda.readthedocs.io/) 2.7.0+ with the GHC backend
- [GHC](https://www.haskell.org/ghc/) 9.6+
- [Haskell packages](https://hackage.haskell.org/): `cborg`, `digest`, `text`, `containers`, `process`, `bytestring`
- [Python](https://python.org/) 3.10+ with [hegel-core](https://pypi.org/project/hegel-core/) installed
- [uv](https://docs.astral.sh/uv/) (recommended, for managing hegel-core)

## Installation

1. Install Agda and GHC (e.g. via [ghcup](https://www.haskell.org/ghcup/))
2. Install the Haskell dependencies:
   ```
   cabal install --lib cborg digest text containers process bytestring
   ```
3. Install hegel-core:
   ```
   pip install hegel-core
   ```
4. Clone this repository and register the library:
   ```
   echo "/path/to/hegel-agda/hegel-agda.agda-lib" >> ~/.agda/libraries
   ```

## Quickstart

Here is a minimal Hegel test in Agda:

```agda
module MyTest where

open import Data.Bool.Base using (Bool; true)
open import Data.List.Base using (List; []; _∷_)
open import Data.Integer.Base using (ℤ; +_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)
open import Hegel.FFI

-- Test: generate bounded integers
testIntegers : TestCase → Prim.IO ⊤
testIntegers tc =
  generateFromSchema tc
    (cborMap
      ( (cborText "type"      ,ᵥ cborText "integer")
      ∷ (cborText "min_value" ,ᵥ cborInt (+ 0))
      ∷ (cborText "max_value" ,ᵥ cborInt (+ 100))
      ∷ []))
  Prim.>>= λ _ → Prim.pure tt

main : Prim.IO ⊤
main =
  runHegelTests
    ((pair "integers" testIntegers) ∷ [])
  Prim.>>= λ _ → Prim.pure tt
```

Compile and run:
```bash
agda --compile \
  --ghc-flag="-i hs-support" \
  --ghc-flag="-package-env .ghc.environment.aarch64-linux-9.6.7" \
  --compile-dir=build \
  MyTest.agda

./build/MyTest
```

## Features

- **Hypothesis-quality shrinking**: Failing examples are automatically reduced to minimal reproductions
- **Persistent example database**: Failing examples are saved and replayed across runs
- **Coverage-guided generation**: Branch coverage guides the engine to explore new code paths
- **All Hegel generators**: integers, floats, booleans, text, binary, lists, tuples, dicts, one-of, format strings (emails, URLs, dates, etc.)
- **Control functions**: `assume` (reject test cases), `note` (debug output), `target` (guide search)

## License

MPL-2.0
