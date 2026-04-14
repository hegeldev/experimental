module TestGenerators where

open import Data.Bool.Base using (Bool; true; false; not)
open import Data.List.Base using (List; []; _∷_; length)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ; zero; suc; _≤ᵇ_)
open import Data.Integer.Base as ℤ using (ℤ; +_; -[1+_])
open import Data.String.Base using (String)
open import Data.Product.Base using (_×_; _,_; proj₁; proj₂)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel

-- ============================================================================
-- Test: booleans generator
-- ============================================================================

testBooleans : TestCase → Prim.IO ⊤
testBooleans tc =
  draw tc booleans Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: bounded integers via integersIn
-- ============================================================================

testIntegersIn : TestCase → Prim.IO ⊤
testIntegersIn tc =
  draw tc (integersIn (+ 0) (+ 100)) Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: text generator
-- ============================================================================

testText : TestCase → Prim.IO ⊤
testText tc =
  draw tc text Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: list of booleans (basic path — schema composition)
-- ============================================================================

testListBasic : TestCase → Prim.IO ⊤
testListBasic tc =
  draw tc (lists booleans) Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: map preserves basicness
-- ============================================================================

testMap : TestCase → Prim.IO ⊤
testMap tc =
  draw tc (gmap not booleans) Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: tuples (basic path)
-- ============================================================================

testTuples : TestCase → Prim.IO ⊤
testTuples tc =
  draw tc (tuples booleans (integersIn (+ 0) (+ 10))) Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: sampledFrom
-- ============================================================================

testSampledFrom : TestCase → Prim.IO ⊤
testSampledFrom tc =
  draw tc (sampledFrom ((+ 1) ∷ (+ 2) ∷ (+ 3) ∷ [])) Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: oneOf (composite path)
-- ============================================================================

testOneOf : TestCase → Prim.IO ⊤
testOneOf tc =
  draw tc (oneOf (booleans ∷ booleans ∷ [])) Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: assume control function
-- ============================================================================

testAssume : TestCase → Prim.IO ⊤
testAssume tc =
  draw tc (integersIn (+ 0) (+ 10)) Prim.>>= λ n →
  assume tc true Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Test: floats generator
-- ============================================================================

testFloats : TestCase → Prim.IO ⊤
testFloats tc =
  draw tc floats Prim.>>= λ _ →
  Prim.pure tt

-- ============================================================================
-- Main: run all tests
-- ============================================================================

main : Prim.IO ⊤
main =
  runHegelTests
    ( pair "booleans"    testBooleans
    ∷ pair "integersIn"  testIntegersIn
    ∷ pair "text"        testText
    ∷ pair "listBasic"   testListBasic
    ∷ pair "map"         testMap
    ∷ pair "tuples"      testTuples
    ∷ pair "sampledFrom" testSampledFrom
    ∷ pair "oneOf"       testOneOf
    ∷ pair "assume"      testAssume
    ∷ pair "floats"      testFloats
    ∷ [])
  Prim.>>= λ _ → Prim.pure tt
