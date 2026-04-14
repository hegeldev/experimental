-- | Test utility functions for hegel-agda.
-- These use Hegel to test Hegel: the conformance tests validate basic generation,
-- and these utilities build on that to test higher-level properties.
module TestUtils where

open import Data.Bool.Base using (Bool; true; false; not)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI using (TestCase; Pair; pair; assume; runHegelTest; runHegelTests)
open import Hegel.Generator using (Generator; draw)

{-# FOREIGN GHC
import qualified HegelFFI as H
import Data.Text (unpack)
import System.IO (hPutStrLn, stderr, hFlush)
import System.Exit (exitFailure)
import Control.Exception (throwIO, ErrorCall(..))
#-}

-- ============================================================================
-- FFI helpers for test output and failure
-- ============================================================================

postulate
  printLine  : String → Prim.IO ⊤
  exitFail   : Prim.IO ⊤
  assertFail : Prim.IO ⊤

{-# COMPILE GHC printLine  = \s -> hPutStrLn stderr (unpack s) >> hFlush stderr #-}
{-# COMPILE GHC exitFail   = exitFailure #-}
{-# COMPILE GHC assertFail = throwIO (ErrorCall "assertion failed") #-}

-- ============================================================================
-- Helper: conditionally fail a test case (throws → INTERESTING)
-- ============================================================================

private
  condFail : TestCase → Bool → Prim.IO ⊤
  condFail tc true  = assertFail
  condFail tc false = Prim.pure tt

-- ============================================================================
-- assertAllExamples: every generated value must satisfy the predicate
-- ============================================================================

-- If pred fails for any value, assertFail throws, making the test case
-- INTERESTING. Hegel will shrink to find the minimal counterexample.
assertAllExamples : {A : Set} → Generator A → (A → Bool) → Prim.IO Bool
assertAllExamples gen pred =
  runHegelTest "assertAllExamples" (λ tc →
    draw tc gen Prim.>>= λ a →
    condFail tc (not (pred a)))

-- ============================================================================
-- findAny: find a value satisfying the condition
-- ============================================================================

-- When cond holds, assertFail throws → test FAILS → runHegelTest returns false.
-- findAny inverts the result: test failing = found something = success.
findAny : {A : Set} → Generator A → (A → Bool) → Prim.IO Bool
findAny gen cond =
  runHegelTest "findAny" (λ tc →
    draw tc gen Prim.>>= λ a →
    condFail tc (cond a))
  Prim.>>= λ passed →
  Prim.pure (not passed)

-- ============================================================================
-- assertNoExamples: no generated value should satisfy the condition
-- ============================================================================

-- If any value satisfies cond, assertFail throws → test FAILS.
assertNoExamples : {A : Set} → Generator A → (A → Bool) → Prim.IO Bool
assertNoExamples gen cond =
  runHegelTest "assertNoExamples" (λ tc →
    draw tc gen Prim.>>= λ a →
    condFail tc (cond a))
