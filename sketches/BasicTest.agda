{-
  API Sketch: What Hegel tests should look like in Agda.
  This file is NOT expected to compile. It documents the desired user experience.
-}
module sketches.BasicTest where

open import Hegel

-- =============================================================================
-- DECISION 1: Test entry point
-- =============================================================================
-- Agda has no test framework. Tests are IO actions compiled to executables.
-- The entry point is `runHegelTest : Settings → (TestCase → IO ⊤) → IO ⊤`
-- The user writes `main = runHegelTest settings body`.
--
-- For multiple tests in one file, we provide:
--   runHegelTests : Settings → List (String × (TestCase → IO ⊤)) → IO ⊤

-- =============================================================================
-- DECISION 2: Drawing values — Explicit context passing
-- =============================================================================
-- Agda is an explicitly-typed, purely functional language. Implicit context
-- (thread-local storage) is unidiomatic. The test function receives a TestCase
-- and passes it to `draw`:
--
--   draw : {A : Set} → TestCase → Generator A → IO A

-- =============================================================================
-- DECISION 3: Generator construction — Record defaults + convenience functions
-- =============================================================================
-- Agda has named record fields but not optional arguments. We use:
-- (a) Zero-argument versions with sensible defaults: `integers`, `text`, `booleans`
-- (b) Record-based configuration: `integersWith (record { minValue = just 0 })`
-- (c) Convenience helpers for common cases: `integersIn 0 100`

-- =============================================================================
-- Test 1: Addition is commutative
-- =============================================================================
test-addition-commutative : TestCase → IO ⊤
test-addition-commutative tc = do
  x ← draw tc integers
  y ← draw tc integers
  assert (x + y ≡ᵇ y + x)

-- =============================================================================
-- Test 2: Using assume — division precondition
-- =============================================================================
test-division : TestCase → IO ⊤
test-division tc = do
  x ← draw tc integers
  y ← draw tc integers
  assume tc (not (y ≡ᵇ 0))
  -- x / y should not crash
  let q = x div y
  assert (q * y + (x mod y) ≡ᵇ x)

-- =============================================================================
-- Test 3: Using note — debug output on failure
-- =============================================================================
test-with-note : TestCase → IO ⊤
test-with-note tc = do
  xs ← draw tc (lists integers)
  note tc ("Generated list: " ++ show xs)
  let sorted = sort xs
  note tc ("Sorted: " ++ show sorted)
  assert (isSorted sorted)

-- =============================================================================
-- Test 4: Using target — guide generation toward longer lists
-- =============================================================================
test-with-target : TestCase → IO ⊤
test-with-target tc = do
  xs ← draw tc (lists integers)
  target tc (toFloat (length xs)) "list length"
  assert (reverse (reverse xs) ≡ᵇ xs)

-- =============================================================================
-- Test 5: Generator composition — sorted unique integers in range
-- =============================================================================
test-composition : TestCase → IO ⊤
test-composition tc = do
  xs ← draw tc (lists (integersIn 0 100))
  let unique-sorted = sort (nub xs)
  assert (isSorted unique-sorted)

-- =============================================================================
-- Test 6: Using map on generators
-- =============================================================================
test-map : TestCase → IO ⊤
test-map tc = do
  -- map preserves basicness: this is still a single server request
  even-num ← draw tc (gmap (_* 2) (integersIn 0 50))
  assert (even even-num)

-- =============================================================================
-- Test 7: Using one-of for sum types
-- =============================================================================
data Shape : Set where
  circle : ℤ → Shape
  rect   : ℤ → ℤ → Shape

shapeGen : Generator Shape
shapeGen = oneOf
  ( gmap circle (integersIn 1 100)
  ∷ gmap (λ pair → rect (fst pair) (snd pair))
         (tuples (integersIn 1 50) (integersIn 1 50))
  ∷ [] )

test-shapes : TestCase → IO ⊤
test-shapes tc = do
  s ← draw tc shapeGen
  assert (area s >ᵇ 0)

-- =============================================================================
-- Test 8: Using flat_map for dependent generation
-- =============================================================================
test-flatmap : TestCase → IO ⊤
test-flatmap tc = do
  -- Generate a list whose length is determined by a drawn value
  xs ← draw tc (flatMap (integersIn 1 10) (λ n →
    listsWith (record { minSize = just n ; maxSize = just n }) integers))
  assert (length xs >ᵇ 0)

-- =============================================================================
-- Test 9: Using filter
-- =============================================================================
test-filter : TestCase → IO ⊤
test-filter tc = do
  x ← draw tc (gfilter even? integers)
  assert (even x)

-- =============================================================================
-- Test 10: Configuring settings
-- =============================================================================
main : IO ⊤
main = runHegelTests
  -- Settings with custom test case count
  (record defaultSettings { testCases = 200 })
  ( ("addition commutative" , test-addition-commutative)
  ∷ ("division"             , test-division)
  ∷ ("with note"            , test-with-note)
  ∷ ("shapes"               , test-shapes)
  ∷ [] )
