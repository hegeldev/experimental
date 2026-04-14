-- | Test utility functions for hegel-agda.
-- These use Hegel to test Hegel: the conformance tests validate basic generation,
-- and these utilities build on that to test higher-level properties.
module TestUtils where

open import Data.Bool.Base using (Bool; true; false; not)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI using (TestCase; Pair; pair; assume; runHegelTest; runHegelTests)
open import Hegel.Generator using (Generator; draw)

{-# FOREIGN GHC
import qualified HegelFFI as H
import Data.Text (unpack)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.IO (hPutStrLn, stderr, hFlush)
import System.Exit (exitFailure)
import Control.Exception (throwIO, ErrorCall(..))
#-}

-- ============================================================================
-- FFI helpers
-- ============================================================================

postulate
  printLine  : String → Prim.IO ⊤
  exitFail   : Prim.IO ⊤
  assertFail : Prim.IO ⊤

{-# COMPILE GHC printLine  = \s -> hPutStrLn stderr (unpack s) >> hFlush stderr #-}
{-# COMPILE GHC exitFail   = exitFailure #-}
{-# COMPILE GHC assertFail = throwIO (ErrorCall "assertion failed") #-}

-- ============================================================================
-- IORef for minimal (mutable reference for capturing shrunk value)
-- ============================================================================

postulate
  IORef      : Set → Set
  newIORef   : {A : Set} → A → Prim.IO (IORef A)
  readIORef  : {A : Set} → IORef A → Prim.IO A
  writeIORef : {A : Set} → IORef A → A → Prim.IO ⊤

{-# COMPILE GHC IORef      = type IORef      #-}
{-# COMPILE GHC newIORef   = \_ -> newIORef   #-}
{-# COMPILE GHC readIORef  = \_ -> readIORef  #-}
{-# COMPILE GHC writeIORef = \_ ref a -> writeIORef ref a #-}

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

assertAllExamples : {A : Set} → Generator A → (A → Bool) → Prim.IO Bool
assertAllExamples gen pred =
  runHegelTest "assertAllExamples" (λ tc →
    draw tc gen Prim.>>= λ a →
    condFail tc (not (pred a)))

-- ============================================================================
-- findAny: find a value satisfying the condition
-- ============================================================================

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

assertNoExamples : {A : Set} → Generator A → (A → Bool) → Prim.IO Bool
assertNoExamples gen cond =
  runHegelTest "assertNoExamples" (λ tc →
    draw tc gen Prim.>>= λ a →
    condFail tc (cond a))

-- ============================================================================
-- minimal: find the smallest counterexample satisfying the condition
-- ============================================================================

-- Runs a Hegel test where cond(value) triggers failure. Hegel shrinks to
-- the minimal counterexample. An IORef captures the last failing value,
-- which after shrinking is the minimal one.
minimal : {A : Set} → Generator A → (A → Bool) → Prim.IO (Maybe A)
minimal {A} gen cond =
  newIORef nothing Prim.>>= λ ref →
  runHegelTest "minimal" (λ tc →
    draw tc gen Prim.>>= λ a →
    maybeStore ref a (cond a) Prim.>>= λ _ →
    condFail tc (cond a))
  Prim.>>= λ _ →
  readIORef ref
  where
    maybeStore : IORef (Maybe A) → A → Bool → Prim.IO ⊤
    maybeStore ref a true  = writeIORef ref (just a)
    maybeStore ref a false = Prim.pure tt
