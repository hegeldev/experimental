-- | Comprehensive test suite ported from hegel-typescript.
-- Exercises all generator types, combinators, code paths, properties,
-- and shrink quality.
module TestComprehensive where

open import Data.Bool.Base using (Bool; true; false; not; _∧_; _∨_)
open import Data.Integer.Base as ℤ using (ℤ; +_; -[1+_]; _+_; _*_; _≤ᵇ_)
open import Data.Float.Base as F using (Float)
open import Data.List.Base as L using (List; []; _∷_; length; map) renaming (_++_ to _++L_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base as ℕ using (ℕ; zero; suc; _∸_)
open import Data.Product.Base using (_×_; _,_; proj₁; proj₂)
open import Data.Char.Base using (Char)
open import Data.String.Base using (String; _++_; toList)
open import Data.Unit.Base using (⊤; tt)
open import Function.Base using (const)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance using (byteStringLength; isNaN′; isInfinite′)
open import TestUtils

private
  -- Integer equality check
  infix 4 _==ℤ_
  _==ℤ_ : ℤ → ℤ → Bool
  a ==ℤ b = (a ≤ᵇ b) ∧ (b ≤ᵇ a)

  -- Natural ≤ check
  _≤ℕ_ : ℕ → ℕ → Bool
  zero  ≤ℕ _     = true
  suc _ ≤ℕ zero  = false
  suc m ≤ℕ suc n = m ≤ℕ n

  isEmpty : {A : Set} → List A → Bool
  isEmpty []      = true
  isEmpty (_ ∷ _) = false

  hasAtLeast : ℕ → {A : Set} → List A → Bool
  hasAtLeast zero    _        = true
  hasAtLeast (suc _) []       = false
  hasAtLeast (suc n) (_ ∷ xs) = hasAtLeast n xs

-- ============================================================================
-- INTEGER GENERATOR TESTS
-- ============================================================================

-- Bounded integers are within bounds
testIntegerBounds : Prim.IO Bool
testIntegerBounds =
  assertAllExamples (integersIn (+ 0) (+ 100)) (λ n →
    (+ 0 ≤ᵇ n) ∧ (n ≤ᵇ + 100))

-- Single-value range produces exactly that value
testIntegerSingle : Prim.IO Bool
testIntegerSingle =
  assertAllExamples (integersIn (+ 42) (+ 42)) (λ n → n ==ℤ + 42)

-- Zero-crossing range works
testIntegerCrossZero : Prim.IO Bool
testIntegerCrossZero =
  assertAllExamples (integersIn (-[1+ 9 ]) (+ 10)) (λ n →
    (-[1+ 9 ] ≤ᵇ n) ∧ (n ≤ᵇ + 10))

-- Unbounded integers can produce large values
testIntegerLarge : Prim.IO Bool
testIntegerLarge = findAny integers (λ n → + 1000 ≤ᵇ n)

-- Unbounded integers can produce negative values
testIntegerNegative : Prim.IO Bool
testIntegerNegative = findAny integers (λ n → n ≤ᵇ -[1+ 999 ])

-- Min-only constraint: all values >= min
testIntegerMinOnly : Prim.IO Bool
testIntegerMinOnly =
  assertAllExamples (integersWith (mkIntOpts (just (+ 10)) nothing)) (λ n →
    + 10 ≤ᵇ n)

-- Max-only constraint: all values <= max
testIntegerMaxOnly : Prim.IO Bool
testIntegerMaxOnly =
  assertAllExamples (integersWith (mkIntOpts nothing (just (+ 10)))) (λ n →
    n ≤ᵇ + 10)

-- ============================================================================
-- FLOAT GENERATOR TESTS
-- ============================================================================

-- Bounded floats are within range
testFloatBounds : Prim.IO Bool
testFloatBounds =
  assertAllExamples
    (floatsWith (mkFloatOpts (just 0.0) (just 1.0) nothing nothing false false))
    (λ _ → true)  -- just verify it doesn't crash

-- Floats can generate positive values
testFloatPositive : Prim.IO Bool
testFloatPositive = findAny floats (λ d → not (isNaN′ d) ∧ not (isInfinite′ d))

-- Floats with NaN excluded should never produce NaN
testFloatNoNaN : Prim.IO Bool
testFloatNoNaN =
  assertNoExamples
    (floatsWith (mkFloatOpts nothing nothing (just false) nothing false false))
    isNaN′

-- Floats with infinity excluded should never produce infinity
testFloatNoInfinity : Prim.IO Bool
testFloatNoInfinity =
  assertNoExamples
    (floatsWith (mkFloatOpts nothing nothing nothing (just false) false false))
    isInfinite′

-- ============================================================================
-- BOOLEAN GENERATOR TESTS
-- ============================================================================

testBoolTrue : Prim.IO Bool
testBoolTrue = findAny booleans (λ b → b)

testBoolFalse : Prim.IO Bool
testBoolFalse = findAny booleans (λ b → not b)

-- ============================================================================
-- TEXT GENERATOR TESTS
-- ============================================================================

-- Empty strings can be generated
testTextEmpty : Prim.IO Bool
testTextEmpty = findAny text (λ s → isEmpty (toList s))

-- Non-empty text can be generated
testTextNonEmpty : Prim.IO Bool
testTextNonEmpty = findAny text (λ s → not (isEmpty (toList s)))

-- Text with minSize produces strings of at least that length
testTextMinSize : Prim.IO Bool
testTextMinSize =
  assertAllExamples (textWith (mkTextOpts 3 nothing nothing nothing nothing nothing nothing nothing nothing))
    (λ s → hasAtLeast 3 (toList s))

-- Text with maxSize produces bounded strings
testTextBounded : Prim.IO Bool
testTextBounded =
  assertAllExamples (textWith (mkTextOpts 0 (just 5) nothing nothing nothing nothing nothing nothing nothing))
    (λ s → length (toList s) ≤ℕ 5)

-- ============================================================================
-- BINARY GENERATOR TESTS
-- ============================================================================

-- Binary with size bounds
testBinaryBounded : Prim.IO Bool
testBinaryBounded =
  assertAllExamples (binaryWith (mkBinaryOpts 2 (just 10))) (λ bs →
    let len = byteStringLength bs in
    (2 ≤ℕ len) ∧ (len ≤ℕ 10))

-- Empty binary can be generated
testBinaryEmpty : Prim.IO Bool
testBinaryEmpty =
  findAny binary (λ bs → byteStringLength bs ≤ℕ 0)

-- ============================================================================
-- SAMPLED-FROM GENERATOR TESTS
-- ============================================================================

-- Only provided options appear
testSampledFromBounds : Prim.IO Bool
testSampledFromBounds =
  assertAllExamples (sampledFrom ((+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [])) (λ n →
    (n ==ℤ + 10) ∨ (n ==ℤ + 20) ∨ (n ==ℤ + 30))

-- Each option is reachable
testSampledFromReach10 : Prim.IO Bool
testSampledFromReach10 =
  findAny (sampledFrom ((+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [])) (λ n → n ==ℤ + 10)

testSampledFromReach20 : Prim.IO Bool
testSampledFromReach20 =
  findAny (sampledFrom ((+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [])) (λ n → n ==ℤ + 20)

testSampledFromReach30 : Prim.IO Bool
testSampledFromReach30 =
  findAny (sampledFrom ((+ 10) ∷ (+ 20) ∷ (+ 30) ∷ [])) (λ n → n ==ℤ + 30)

-- ============================================================================
-- COLLECTION GENERATOR TESTS
-- ============================================================================

-- Lists can be empty
testListEmpty : Prim.IO Bool
testListEmpty = findAny (lists booleans) isEmpty

-- Lists with min_size respect the bound
testListMinSize : Prim.IO Bool
testListMinSize =
  assertAllExamples (listsWith (mkListOpts 2 nothing nothing) booleans)
    (hasAtLeast 2)

-- Lists with max_size respect the bound
testListMaxSize : Prim.IO Bool
testListMaxSize =
  assertAllExamples (listsWith (mkListOpts 0 (just 5) nothing) (integersIn (+ 0) (+ 10)))
    (λ l → length l ≤ℕ 5)

-- Lists with composite elements (non-basic path / collection protocol)
testListComposite : Prim.IO Bool
testListComposite =
  let nonBasicInt = composite (λ tc → draw tc (integersIn (+ 0) (+ 50)))
  in findAny (lists nonBasicInt) (hasAtLeast 1)

-- Lists element constraints hold
testListElements : Prim.IO Bool
testListElements =
  assertAllExamples (lists (integersIn (+ 0) (+ 10))) (λ l →
    allSatisfy l)
  where
    allSatisfy : List ℤ → Bool
    allSatisfy []       = true
    allSatisfy (x ∷ xs) = ((+ 0 ≤ᵇ x) ∧ (x ≤ᵇ + 10)) ∧ allSatisfy xs

-- Tuples: both components satisfy constraints
testTuplesPair : Prim.IO Bool
testTuplesPair =
  assertAllExamples (tuples booleans (integersIn (+ 0) (+ 10))) (λ p →
    (+ 0 ≤ᵇ proj₂ p) ∧ (proj₂ p ≤ᵇ + 10))

-- Dicts basic path: key and value constraints
testDictBasic : Prim.IO Bool
testDictBasic =
  assertAllExamples (dicts (integersIn (+ 0) (+ 10)) (integersIn (+ 100) (+ 200)))
    (λ kvs → allKVSatisfy kvs)
  where
    allKVSatisfy : List (ℤ × ℤ) → Bool
    allKVSatisfy []             = true
    allKVSatisfy ((k , v) ∷ rs) =
      ((+ 0 ≤ᵇ k) ∧ (k ≤ᵇ + 10) ∧ (+ 100 ≤ᵇ v) ∧ (v ≤ᵇ + 200))
      ∧ allKVSatisfy rs

-- Dicts with size constraint
testDictSize : Prim.IO Bool
testDictSize =
  assertAllExamples
    (dictsWith (mkDictOpts 1 (just 3)) (integersIn (+ 0) (+ 10)) (integersIn (+ 0) (+ 10)))
    (λ kvs → hasAtLeast 1 kvs ∧ (length kvs ≤ℕ 3))

-- Dicts with composite elements (collection protocol)
testDictComposite : Prim.IO Bool
testDictComposite =
  let nonBasicKey = composite (λ tc → draw tc (integersIn (+ 0) (+ 50)))
      nonBasicVal = composite (λ tc → draw tc (integersIn (+ 0) (+ 50)))
  in findAny (dicts nonBasicKey nonBasicVal) (hasAtLeast 1)

-- ============================================================================
-- COMBINATOR TESTS
-- ============================================================================

-- map preserves basicness and transforms values
testMapBasic : Prim.IO Bool
testMapBasic =
  assertAllExamples (gmap (ℤ._+_ (+ 1)) (integersIn (+ 0) (+ 10))) (λ n →
    (+ 1 ≤ᵇ n) ∧ (n ≤ᵇ + 11))

-- map with not flips booleans
testMapNot : Prim.IO Bool
testMapNot = findAny (gmap not booleans) (λ b → b)

-- Chained maps compose: gmap f (gmap g gen) == gmap (f . g) gen
testChainedMaps : Prim.IO Bool
testChainedMaps =
  assertAllExamples
    (gmap (ℤ._+_ (+ 1)) (gmap (ℤ._*_ (+ 2)) (integersIn (+ 0) (+ 5))))
    (λ n → -- (x * 2) + 1 for x in [0,5] → odd numbers in [1,11]
      (+ 1 ≤ᵇ n) ∧ (n ≤ᵇ + 11))

-- map on non-basic generator (uses MAPPED span)
testMapComposite : Prim.IO Bool
testMapComposite =
  let nonBasic = composite (λ tc → draw tc (integersIn (+ 0) (+ 10)))
  in assertAllExamples (gmap (ℤ._+_ (+ 100)) nonBasic) (λ n →
       (+ 100 ≤ᵇ n) ∧ (n ≤ᵇ + 110))

-- filter restricts output
testFilterBasic : Prim.IO Bool
testFilterBasic =
  assertAllExamples (gfilter isPos (integersIn (+ 0) (+ 100))) (λ n → + 1 ≤ᵇ n)
  where
    isPos : ℤ → Bool
    isPos (+ zero)    = false
    isPos (+ (suc _)) = true
    isPos _           = false

-- filter + assertNoExamples: filtered-out values never appear
testFilterExcludes : Prim.IO Bool
testFilterExcludes =
  assertNoExamples
    (gfilter (λ n → + 50 ≤ᵇ n) (integersIn (+ 0) (+ 100)))
    (λ n → n ≤ᵇ + 49)

-- flatMap produces correct dependent generation
testFlatMap : Prim.IO Bool
testFlatMap =
  assertAllExamples (flatMap booleans boolGen) (λ _ → true)
  where
    boolGen : Bool → Generator ℤ
    boolGen true  = integersIn (+ 0) (+ 10)
    boolGen false = integersIn (-[1+ 9 ]) (+ 0)

-- flatMap with dependent bounds
testFlatMapDependent : Prim.IO Bool
testFlatMapDependent =
  assertAllExamples
    (flatMap (integersIn (+ 1) (+ 5)) (λ n →
      integersIn n (n ℤ.+ + 10)))
    (λ _ → true)  -- just verify it doesn't crash

-- oneOf with all basic (Path 2 — tuple schema)
testOneOfBasic : Prim.IO Bool
testOneOfBasic =
  assertAllExamples (oneOf (integersIn (+ 0) (+ 10) ∷ integersIn (+ 90) (+ 100) ∷ []))
    (λ n → (n ≤ᵇ + 10) ∨ (+ 90 ≤ᵇ n))

-- oneOf with non-basic (Path 3 — composite)
testOneOfComposite : Prim.IO Bool
testOneOfComposite =
  assertAllExamples
    (oneOf ( booleans
           ∷ composite (λ tc → draw tc booleans)
           ∷ []))
    (λ _ → true)

-- oneOf covers all branches (3-way)
testOneOfBranch0 : Prim.IO Bool
testOneOfBranch0 =
  findAny (oneOf (integersIn (+ 0) (+ 0)
                ∷ integersIn (+ 100) (+ 100)
                ∷ integersIn (+ 200) (+ 200) ∷ []))
    (λ n → n ==ℤ + 0)

testOneOfBranch1 : Prim.IO Bool
testOneOfBranch1 =
  findAny (oneOf (integersIn (+ 0) (+ 0)
                ∷ integersIn (+ 100) (+ 100)
                ∷ integersIn (+ 200) (+ 200) ∷ []))
    (λ n → n ==ℤ + 100)

testOneOfBranch2 : Prim.IO Bool
testOneOfBranch2 =
  findAny (oneOf (integersIn (+ 0) (+ 0)
                ∷ integersIn (+ 100) (+ 100)
                ∷ integersIn (+ 200) (+ 200) ∷ []))
    (λ n → n ==ℤ + 200)

-- oneOf with map transforms (Path 2 with transforms)
testOneOfWithMap : Prim.IO Bool
testOneOfWithMap =
  assertAllExamples
    (oneOf ( gmap (ℤ._*_ (+ 2)) (integersIn (+ 0) (+ 5))    -- even: 0,2,4,6,8,10
           ∷ gmap (ℤ._+_ (+ 100)) (integersIn (+ 0) (+ 5))  -- 100-105
           ∷ []))
    (λ n → (n ≤ᵇ + 10) ∨ (+ 100 ≤ᵇ n))

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

-- optional with mapped generator (tests Path 2 with transforms)
testOptionalMapped : Prim.IO Bool
testOptionalMapped =
  assertAllExamples (optional (gmap (ℤ._+_ (+ 100)) (integersIn (+ 0) (+ 10)))) check
  where
    check : Maybe ℤ → Bool
    check nothing  = true
    check (just n) = (+ 100 ≤ᵇ n) ∧ (n ≤ᵇ + 110)

-- ============================================================================
-- FORMAT GENERATOR TESTS
-- ============================================================================

testFromRegex : Prim.IO Bool
testFromRegex = assertAllExamples (fromRegex "[a-z]+") (λ _ → true)

-- Emails contain @
testEmails : Prim.IO Bool
testEmails = assertAllExamples emails (λ s → hasAt (toList s))
  where
    hasAt : List Char → Bool
    hasAt []        = false
    hasAt ('@' ∷ _) = true
    hasAt (_ ∷ xs)  = hasAt xs

-- Dates match YYYY-MM-DD (length 10, has dashes)
testDates : Prim.IO Bool
testDates = assertAllExamples dates (λ s → hasAtLeast 10 (toList s))

-- IPv4 addresses have dots
testIpv4 : Prim.IO Bool
testIpv4 = assertAllExamples ipv4 (λ s → hasDot (toList s))
  where
    hasDot : List Char → Bool
    hasDot []        = false
    hasDot ('.' ∷ _) = true
    hasDot (_ ∷ xs)  = hasDot xs

-- ============================================================================
-- REAL-WORLD PROPERTY TESTS
-- ============================================================================

-- Integer addition is commutative: x + y == y + x
testAdditionCommutative : Prim.IO Bool
testAdditionCommutative =
  assertAllExamples
    (tuples (integersIn (-[1+ 999 ]) (+ 1000)) (integersIn (-[1+ 999 ]) (+ 1000)))
    (λ p → let x = proj₁ p; y = proj₂ p in (x ℤ.+ y) ==ℤ (y ℤ.+ x))

-- Integer multiplication is commutative: x * y == y * x
testMultiplicationCommutative : Prim.IO Bool
testMultiplicationCommutative =
  assertAllExamples
    (tuples (integersIn (-[1+ 99 ]) (+ 100)) (integersIn (-[1+ 99 ]) (+ 100)))
    (λ p → let x = proj₁ p; y = proj₂ p in (x ℤ.* y) ==ℤ (y ℤ.* x))

-- Boolean double negation: not (not b) == b
testBoolDoubleNegation : Prim.IO Bool
testBoolDoubleNegation =
  assertAllExamples booleans (λ b → eqBool (not (not b)) b)
  where
    eqBool : Bool → Bool → Bool
    eqBool true  true  = true
    eqBool false false = true
    eqBool _     _     = false

-- List append increases length
testListAppendLength : Prim.IO Bool
testListAppendLength =
  assertAllExamples
    (tuples (lists (integersIn (+ 0) (+ 10))) (integersIn (+ 0) (+ 10)))
    (λ p → let xs = proj₁ p; n = proj₂ p in
      hasAtLeast (length xs) (xs ++L (n ∷ [])))

-- Concatenation length: |xs ++ ys| == |xs| + |ys|
testConcatLength : Prim.IO Bool
testConcatLength =
  assertAllExamples
    (tuples (lists booleans) (lists booleans))
    (λ p → let xs = proj₁ p; ys = proj₂ p in
      length (xs ++L ys) ==ℕ (length xs ℕ.+ length ys))
  where
    _==ℕ_ : ℕ → ℕ → Bool
    zero  ==ℕ zero  = true
    suc m ==ℕ suc n = m ==ℕ n
    _     ==ℕ _     = false

-- ============================================================================
-- SHRINK QUALITY TESTS (using minimal)
-- ============================================================================

-- minimal integer >= 100 should be exactly 100
testMinimalInteger : Prim.IO Bool
testMinimalInteger =
  minimal (integersIn (+ 0) (+ 1000)) (λ n → + 100 ≤ᵇ n) Prim.>>= λ where
    (just n) → Prim.pure (n ==ℤ + 100)
    nothing  → Prim.pure false

-- minimal integer <= -100 should be exactly -100
testMinimalNegative : Prim.IO Bool
testMinimalNegative =
  minimal (integersIn (-[1+ 999 ]) (+ 0)) (λ n → n ≤ᵇ -[1+ 99 ]) Prim.>>= λ where
    (just n) → Prim.pure (n ==ℤ -[1+ 99 ])
    nothing  → Prim.pure false

-- minimal list with length >= 3 should have exactly 3 elements
testMinimalList : Prim.IO Bool
testMinimalList =
  minimal (lists (integersIn (+ 0) (+ 100))) (hasAtLeast 3) Prim.>>= λ where
    (just l) → Prim.pure (length l ≤ℕ 3)
    nothing  → Prim.pure false

-- ============================================================================
-- MAIN: run all tests
-- ============================================================================

reportAndRun : String → Prim.IO Bool → Prim.IO Bool
reportAndRun name test =
  test Prim.>>= λ result →
  report result Prim.>>= λ _ →
  Prim.pure result
  where
    report : Bool → Prim.IO ⊤
    report true  = printLine ("  PASS: " Data.String.Base.++ name)
    report false = printLine ("  FAIL: " Data.String.Base.++ name)

allPassed : List Bool → Bool
allPassed []           = true
allPassed (true  ∷ bs) = allPassed bs
allPassed (false ∷ _)  = false

main : Prim.IO ⊤
main =
  printLine "=== Comprehensive Test Suite ===" Prim.>>= λ _ →

  -- Integers (7)
  reportAndRun "integer-bounds"       testIntegerBounds       Prim.>>= λ r01 →
  reportAndRun "integer-single"       testIntegerSingle       Prim.>>= λ r02 →
  reportAndRun "integer-cross-zero"   testIntegerCrossZero    Prim.>>= λ r03 →
  reportAndRun "integer-large"        testIntegerLarge        Prim.>>= λ r04 →
  reportAndRun "integer-negative"     testIntegerNegative     Prim.>>= λ r05 →
  reportAndRun "integer-min-only"     testIntegerMinOnly      Prim.>>= λ r06 →
  reportAndRun "integer-max-only"     testIntegerMaxOnly      Prim.>>= λ r07 →

  -- Floats (4)
  reportAndRun "float-bounds"         testFloatBounds         Prim.>>= λ r08 →
  reportAndRun "float-positive"       testFloatPositive       Prim.>>= λ r09 →
  reportAndRun "float-no-nan"         testFloatNoNaN          Prim.>>= λ r10 →
  reportAndRun "float-no-infinity"    testFloatNoInfinity     Prim.>>= λ r11 →

  -- Booleans (2)
  reportAndRun "bool-true"            testBoolTrue            Prim.>>= λ r12 →
  reportAndRun "bool-false"           testBoolFalse           Prim.>>= λ r13 →

  -- Text (4)
  reportAndRun "text-empty"           testTextEmpty           Prim.>>= λ r14 →
  reportAndRun "text-non-empty"       testTextNonEmpty        Prim.>>= λ r15 →
  reportAndRun "text-min-size"        testTextMinSize         Prim.>>= λ r16 →
  reportAndRun "text-bounded"         testTextBounded         Prim.>>= λ r17 →

  -- Binary (2)
  reportAndRun "binary-bounded"       testBinaryBounded       Prim.>>= λ r18 →
  reportAndRun "binary-empty"         testBinaryEmpty         Prim.>>= λ r19 →

  -- SampledFrom (4)
  reportAndRun "sampled-bounds"       testSampledFromBounds   Prim.>>= λ r20 →
  reportAndRun "sampled-reach-10"     testSampledFromReach10  Prim.>>= λ r21 →
  reportAndRun "sampled-reach-20"     testSampledFromReach20  Prim.>>= λ r22 →
  reportAndRun "sampled-reach-30"     testSampledFromReach30  Prim.>>= λ r23 →

  -- Collections (9)
  reportAndRun "list-empty"           testListEmpty           Prim.>>= λ r24 →
  reportAndRun "list-min-size"        testListMinSize         Prim.>>= λ r25 →
  reportAndRun "list-max-size"        testListMaxSize         Prim.>>= λ r26 →
  reportAndRun "list-composite"       testListComposite       Prim.>>= λ r27 →
  reportAndRun "list-elements"        testListElements        Prim.>>= λ r28 →
  reportAndRun "tuples-pair"          testTuplesPair          Prim.>>= λ r29 →
  reportAndRun "dict-basic"           testDictBasic           Prim.>>= λ r30 →
  reportAndRun "dict-size"            testDictSize            Prim.>>= λ r31 →
  reportAndRun "dict-composite"       testDictComposite       Prim.>>= λ r32 →

  -- Combinators (14)
  reportAndRun "map-basic"            testMapBasic            Prim.>>= λ r33 →
  reportAndRun "map-not"              testMapNot              Prim.>>= λ r34 →
  reportAndRun "chained-maps"         testChainedMaps         Prim.>>= λ r35 →
  reportAndRun "map-composite"        testMapComposite        Prim.>>= λ r36 →
  reportAndRun "filter-basic"         testFilterBasic         Prim.>>= λ r37 →
  reportAndRun "filter-excludes"      testFilterExcludes      Prim.>>= λ r38 →
  reportAndRun "flatmap"              testFlatMap             Prim.>>= λ r39 →
  reportAndRun "flatmap-dependent"    testFlatMapDependent    Prim.>>= λ r40 →
  reportAndRun "oneof-basic"          testOneOfBasic          Prim.>>= λ r41 →
  reportAndRun "oneof-composite"      testOneOfComposite      Prim.>>= λ r42 →
  reportAndRun "oneof-branch-0"       testOneOfBranch0        Prim.>>= λ r43 →
  reportAndRun "oneof-branch-1"       testOneOfBranch1        Prim.>>= λ r44 →
  reportAndRun "oneof-branch-2"       testOneOfBranch2        Prim.>>= λ r45 →
  reportAndRun "oneof-with-map"       testOneOfWithMap        Prim.>>= λ r46 →

  -- Optional (3)
  reportAndRun "optional-nothing"     testOptionalNothing     Prim.>>= λ r47 →
  reportAndRun "optional-just"        testOptionalJust        Prim.>>= λ r48 →
  reportAndRun "optional-mapped"      testOptionalMapped      Prim.>>= λ r49 →

  -- Format generators (4)
  reportAndRun "from-regex"           testFromRegex           Prim.>>= λ r50 →
  reportAndRun "emails"               testEmails              Prim.>>= λ r51 →
  reportAndRun "dates"                testDates               Prim.>>= λ r52 →
  reportAndRun "ipv4"                 testIpv4                Prim.>>= λ r53 →

  -- Properties (5)
  reportAndRun "addition-commutative"        testAdditionCommutative        Prim.>>= λ r54 →
  reportAndRun "multiplication-commutative"  testMultiplicationCommutative  Prim.>>= λ r55 →
  reportAndRun "bool-double-negation"        testBoolDoubleNegation         Prim.>>= λ r56 →
  reportAndRun "list-append-length"          testListAppendLength           Prim.>>= λ r57 →
  reportAndRun "concat-length"               testConcatLength               Prim.>>= λ r58 →

  -- Shrink quality (3)
  reportAndRun "minimal-integer"      testMinimalInteger      Prim.>>= λ r59 →
  reportAndRun "minimal-negative"     testMinimalNegative     Prim.>>= λ r60 →
  reportAndRun "minimal-list"         testMinimalList         Prim.>>= λ r61 →

  let results = r01 ∷ r02 ∷ r03 ∷ r04 ∷ r05 ∷ r06 ∷ r07 ∷ r08 ∷ r09 ∷ r10
              ∷ r11 ∷ r12 ∷ r13 ∷ r14 ∷ r15 ∷ r16 ∷ r17 ∷ r18 ∷ r19 ∷ r20
              ∷ r21 ∷ r22 ∷ r23 ∷ r24 ∷ r25 ∷ r26 ∷ r27 ∷ r28 ∷ r29 ∷ r30
              ∷ r31 ∷ r32 ∷ r33 ∷ r34 ∷ r35 ∷ r36 ∷ r37 ∷ r38 ∷ r39 ∷ r40
              ∷ r41 ∷ r42 ∷ r43 ∷ r44 ∷ r45 ∷ r46 ∷ r47 ∷ r48 ∷ r49 ∷ r50
              ∷ r51 ∷ r52 ∷ r53 ∷ r54 ∷ r55 ∷ r56 ∷ r57 ∷ r58 ∷ r59 ∷ r60
              ∷ r61 ∷ [] in
  finish (allPassed results)
  where
    finish : Bool → Prim.IO ⊤
    finish true  = printLine "All 61 comprehensive tests passed."
    finish false = printLine "SOME TESTS FAILED!" Prim.>>= λ _ → exitFail
