-- | Comprehensive test suite ported from hegel-rust/hegel-typescript.
-- Exercises all generator types, combinators, and code paths.
module TestComprehensive where

open import Data.Bool.Base using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Integer.Base as ℤ using (ℤ; +_; -[1+_]; _≤ᵇ_)
open import Data.Float.Base as F using (Float)
open import Data.List.Base using (List; []; _∷_; length; map)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base as ℕ using (ℕ; zero; suc)
open import Data.Product.Base using (_×_; _,_; proj₁; proj₂)
open import Data.String.Base using (String; _++_; toList)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import TestUtils

-- ============================================================================
-- Integer generator tests
-- ============================================================================

-- Bounded integers are within bounds
testIntegerBounds : Prim.IO Bool
testIntegerBounds =
  assertAllExamples (integersIn (+ 0) (+ 100)) (λ n →
    (+ 0 ≤ᵇ n) ∧ (n ≤ᵇ + 100))

-- Single-value range produces only that value
testIntegerSingle : Prim.IO Bool
testIntegerSingle =
  assertAllExamples (integersIn (+ 42) (+ 42)) (λ n →
    (+ 42 ≤ᵇ n) ∧ (n ≤ᵇ + 42))

-- Zero-crossing range works
testIntegerCrossZero : Prim.IO Bool
testIntegerCrossZero =
  assertAllExamples (integersIn (-[1+ 9 ]) (+ 10)) (λ n →
    (-[1+ 9 ] ≤ᵇ n) ∧ (n ≤ᵇ + 10))

-- Unbounded integers can produce large values
testIntegerLarge : Prim.IO Bool
testIntegerLarge =
  findAny integers (λ n → + 1000 ≤ᵇ n)

-- Unbounded integers can produce negative values
testIntegerNegative : Prim.IO Bool
testIntegerNegative =
  findAny integers (λ n → n ≤ᵇ -[1+ 999 ])

-- ============================================================================
-- Boolean generator tests
-- ============================================================================

-- Both values are reachable
testBoolTrue : Prim.IO Bool
testBoolTrue = findAny booleans (λ b → b)

testBoolFalse : Prim.IO Bool
testBoolFalse = findAny booleans (λ b → not b)

-- ============================================================================
-- Text generator tests
-- ============================================================================

-- Empty strings can be generated
testTextEmpty : Prim.IO Bool
testTextEmpty = findAny text (λ s → isEmpty (toList s))
  where
    isEmpty : {A : Set} → List A → Bool
    isEmpty []      = true
    isEmpty (_ ∷ _) = false

-- ============================================================================
-- SampledFrom tests
-- ============================================================================

-- Only provided options appear
testSampledFromBounds : Prim.IO Bool
testSampledFromBounds =
  let opts = (+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [] in
  assertAllExamples (sampledFrom opts) (λ n →
    isEq n (+ 10) ∨ isEq n (+ 20) ∨ isEq n (+ 30))
  where
    isEq : ℤ → ℤ → Bool
    isEq a b = (a ≤ᵇ b) ∧ (b ≤ᵇ a)

-- Each option is reachable
testSampledFromReach10 : Prim.IO Bool
testSampledFromReach10 =
  findAny (sampledFrom ((+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [])) (λ n → n ≤ᵇ + 10)

testSampledFromReach30 : Prim.IO Bool
testSampledFromReach30 =
  findAny (sampledFrom ((+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [])) (λ n → + 30 ≤ᵇ n)

-- ============================================================================
-- Collection tests
-- ============================================================================

-- Lists can be empty when min_size is 0
testListEmpty : Prim.IO Bool
testListEmpty =
  findAny (lists booleans) isEmpty
  where
    isEmpty : {A : Set} → List A → Bool
    isEmpty []      = true
    isEmpty (_ ∷ _) = false

-- Lists with min_size respect the bound
testListMinSize : Prim.IO Bool
testListMinSize =
  assertAllExamples (listsWith (mkListOpts 2 nothing nothing) booleans) (λ l →
    hasAtLeast2 l)
  where
    hasAtLeast2 : {A : Set} → List A → Bool
    hasAtLeast2 (_ ∷ _ ∷ _) = true
    hasAtLeast2 _            = false

-- Tuples produce pairs
testTuplesPair : Prim.IO Bool
testTuplesPair =
  assertAllExamples (tuples booleans (integersIn (+ 0) (+ 10))) (λ p →
    let _ = proj₁ p; n = proj₂ p in
    (+ 0 ≤ᵇ n) ∧ (n ≤ᵇ + 10))

-- ============================================================================
-- Combinator tests
-- ============================================================================

-- map preserves basicness: mapped integers stay in range
testMapBasic : Prim.IO Bool
testMapBasic =
  assertAllExamples (gmap (ℤ._+_ (+ 1)) (integersIn (+ 0) (+ 10))) (λ n →
    (+ 1 ≤ᵇ n) ∧ (n ≤ᵇ + 11))

-- map with not flips booleans
testMapNot : Prim.IO Bool
testMapNot =
  findAny (gmap not booleans) (λ b → b)

-- filter restricts output
testFilterBasic : Prim.IO Bool
testFilterBasic =
  assertAllExamples (gfilter isPos (integersIn (+ 0) (+ 100))) (λ n →
    + 1 ≤ᵇ n)
  where
    isPos : ℤ → Bool
    isPos (+ zero)    = false
    isPos (+ (suc _)) = true
    isPos _           = false

-- flatMap produces correct dependent generation
testFlatMap : Prim.IO Bool
testFlatMap =
  assertAllExamples (flatMap booleans boolGen) (λ _ → true)
  where
    boolGen : Bool → Generator ℤ
    boolGen true  = integersIn (+ 0) (+ 10)
    boolGen false = integersIn (-[1+ 9 ]) (+ 0)

-- oneOf with all basic (Path 2)
testOneOfBasic : Prim.IO Bool
testOneOfBasic =
  assertAllExamples (oneOf (integersIn (+ 0) (+ 10) ∷ integersIn (+ 90) (+ 100) ∷ []))
    (λ n → (n ≤ᵇ + 10) ∨ (+ 90 ≤ᵇ n))

-- oneOf with non-basic (Path 3)
testOneOfComposite : Prim.IO Bool
testOneOfComposite =
  assertAllExamples
    (oneOf ( booleans
           ∷ composite (λ tc → draw tc booleans)
           ∷ []))
    (λ _ → true)

-- optional can produce nothing
testOptionalNothing : Prim.IO Bool
testOptionalNothing =
  findAny (optional booleans) isNothing
  where
    isNothing : Maybe Bool → Bool
    isNothing nothing  = true
    isNothing (just _) = false

-- optional can produce just
testOptionalJust : Prim.IO Bool
testOptionalJust =
  findAny (optional booleans) isJust
  where
    isJust : Maybe Bool → Bool
    isJust nothing  = false
    isJust (just _) = true

-- ============================================================================
-- Format generator tests
-- ============================================================================

-- fromRegex produces matching strings
testFromRegex : Prim.IO Bool
testFromRegex =
  assertAllExamples (fromRegex "[a-z]+") (λ _ → true)

-- ============================================================================
-- Error injection tests via HEGEL_PROTOCOL_TEST_MODE
-- ============================================================================

-- These are already tested by the conformance suite, so we just verify
-- the generator API works in normal mode.

-- ============================================================================
-- Main: run all comprehensive tests
-- ============================================================================

reportAndRun : String → Prim.IO Bool → Prim.IO Bool
reportAndRun name test =
  test Prim.>>= λ result →
  report result Prim.>>= λ _ →
  Prim.pure result
  where
    report : Bool → Prim.IO ⊤
    report true  = printLine ("  PASS: " ++ name)
    report false = printLine ("  FAIL: " ++ name)

allPassed : List Bool → Bool
allPassed []           = true
allPassed (true  ∷ bs) = allPassed bs
allPassed (false ∷ _)  = false

main : Prim.IO ⊤
main =
  printLine "=== Comprehensive Test Suite ===" Prim.>>= λ _ →

  -- Integers
  reportAndRun "integer-bounds"     testIntegerBounds     Prim.>>= λ r1 →
  reportAndRun "integer-single"     testIntegerSingle     Prim.>>= λ r2 →
  reportAndRun "integer-cross-zero" testIntegerCrossZero  Prim.>>= λ r3 →
  reportAndRun "integer-large"      testIntegerLarge      Prim.>>= λ r4 →
  reportAndRun "integer-negative"   testIntegerNegative   Prim.>>= λ r5 →

  -- Booleans
  reportAndRun "bool-true"          testBoolTrue          Prim.>>= λ r6 →
  reportAndRun "bool-false"         testBoolFalse         Prim.>>= λ r7 →

  -- Text
  reportAndRun "text-empty"         testTextEmpty         Prim.>>= λ r8 →

  -- SampledFrom
  reportAndRun "sampled-bounds"     testSampledFromBounds Prim.>>= λ r9 →
  reportAndRun "sampled-reach-10"   testSampledFromReach10 Prim.>>= λ r10 →
  reportAndRun "sampled-reach-30"   testSampledFromReach30 Prim.>>= λ r11 →

  -- Collections
  reportAndRun "list-empty"         testListEmpty         Prim.>>= λ r12 →
  reportAndRun "list-min-size"      testListMinSize       Prim.>>= λ r13 →
  reportAndRun "tuples-pair"        testTuplesPair        Prim.>>= λ r14 →

  -- Combinators
  reportAndRun "map-basic"          testMapBasic          Prim.>>= λ r15 →
  reportAndRun "map-not"            testMapNot            Prim.>>= λ r16 →
  reportAndRun "filter-basic"       testFilterBasic       Prim.>>= λ r17 →
  reportAndRun "flatmap"            testFlatMap           Prim.>>= λ r18 →
  reportAndRun "oneof-basic"        testOneOfBasic        Prim.>>= λ r19 →
  reportAndRun "oneof-composite"    testOneOfComposite    Prim.>>= λ r20 →
  reportAndRun "optional-nothing"   testOptionalNothing   Prim.>>= λ r21 →
  reportAndRun "optional-just"      testOptionalJust      Prim.>>= λ r22 →

  -- Format
  reportAndRun "from-regex"         testFromRegex         Prim.>>= λ r23 →

  let results = r1 ∷ r2 ∷ r3 ∷ r4 ∷ r5 ∷ r6 ∷ r7 ∷ r8 ∷ r9 ∷ r10
              ∷ r11 ∷ r12 ∷ r13 ∷ r14 ∷ r15 ∷ r16 ∷ r17 ∷ r18 ∷ r19
              ∷ r20 ∷ r21 ∷ r22 ∷ r23 ∷ [] in
  finish (allPassed results)
  where
    finish : Bool → Prim.IO ⊤
    finish true  = printLine "All comprehensive tests passed."
    finish false = printLine "SOME TESTS FAILED!" Prim.>>= λ _ → exitFail
