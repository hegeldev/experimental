module TestBasic where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Integer.Base using (ℤ; +_)
open import Data.String.Base using (String)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI

-- A simple test: generate a boolean
testBoolean : TestCase → Prim.IO ⊤
testBoolean tc =
  generateFromSchema tc
    (cborMap ((cborText "type" ,ᵥ cborText "boolean") ∷ []))
  Prim.>>= λ _ → Prim.pure tt

-- A test with bounded integers
testInteger : TestCase → Prim.IO ⊤
testInteger tc =
  generateFromSchema tc
    (cborMap
      ( (cborText "type"      ,ᵥ cborText "integer")
      ∷ (cborText "min_value" ,ᵥ cborInt (+ 0))
      ∷ (cborText "max_value" ,ᵥ cborInt (+ 100))
      ∷ []))
  Prim.>>= λ _ → Prim.pure tt

-- A test using assume
testWithAssume : TestCase → Prim.IO ⊤
testWithAssume tc =
  generateFromSchema tc
    (cborMap
      ( (cborText "type"      ,ᵥ cborText "integer")
      ∷ (cborText "min_value" ,ᵥ cborInt (+ 0))
      ∷ (cborText "max_value" ,ᵥ cborInt (+ 10))
      ∷ []))
  Prim.>>= λ _ →
  assume tc true
  Prim.>>= λ _ →
  Prim.pure tt

main : Prim.IO ⊤
main =
  runHegelTests
    ( (pair "boolean" testBoolean)
    ∷ (pair "integer" testInteger)
    ∷ (pair "assume"  testWithAssume)
    ∷ [])
  Prim.>>= λ _ → Prim.pure tt
