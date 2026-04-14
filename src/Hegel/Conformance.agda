-- | Conformance test infrastructure for hegel-agda.
-- Provides FFI bindings to the Haskell Conformance module, enabling
-- conformance binaries to be written in Agda using the generator API.
module Hegel.Conformance where

open import Data.Bool.Base using (Bool; true; false)
open import Data.Float.Base using (Float)
open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI using (TestCase; Pair; pair; ByteString)

{-# FOREIGN GHC
import qualified Conformance as C
import qualified HegelFFI as H
import qualified Data.Text as T
import qualified Data.ByteString as BS
import Data.Char (ord)
import System.Environment (lookupEnv)
#-}

-- ============================================================================
-- Opaque types from Haskell
-- ============================================================================

postulate
  Params        : Set
  MetricsWriter : Set

{-# COMPILE GHC Params        = type C.Params        #-}
{-# COMPILE GHC MetricsWriter = type C.MetricsWriter  #-}

-- ============================================================================
-- Param accessors
-- ============================================================================

postulate
  getParamInt        : String → Params → Maybe ℤ
  getParamFloat      : String → Params → Maybe Float
  getParamString     : String → Params → Maybe String
  getParamBool       : String → Params → Maybe Bool
  getParamIntList    : String → Params → Maybe (List ℤ)
  getParamStringList : String → Params → Maybe (List String)

{-# COMPILE GHC getParamInt        = \k ps -> fmap fromIntegral (C.paramInt (T.unpack k) ps)      #-}
{-# COMPILE GHC getParamFloat      = \k ps -> C.paramDouble (T.unpack k) ps                       #-}
{-# COMPILE GHC getParamString     = \k ps -> fmap T.pack (C.paramString (T.unpack k) ps)         #-}
{-# COMPILE GHC getParamBool       = \k ps -> C.paramBool (T.unpack k) ps                         #-}
{-# COMPILE GHC getParamIntList    = \k ps -> fmap (map fromIntegral) (C.paramIntList (T.unpack k) ps) #-}
{-# COMPILE GHC getParamStringList = \k ps -> fmap (map T.pack) (C.paramStringList (T.unpack k) ps)   #-}

-- ============================================================================
-- Metrics output
-- ============================================================================

postulate
  writeResult : MetricsWriter → String → Prim.IO ⊤

{-# COMPILE GHC writeResult = \w s -> C.writeMetricStr w (T.unpack s) #-}

-- ============================================================================
-- Conformance runner
-- ============================================================================

postulate
  runConformance : (TestCase → Params → MetricsWriter → Prim.IO ⊤) → Prim.IO ⊤

{-# COMPILE GHC runConformance = C.runConformanceAgda #-}

-- ============================================================================
-- Utility functions for conformance output formatting
-- ============================================================================

postulate
  -- Show an integer as a decimal string
  showℤ : ℤ → String
  -- Show a float, handling NaN/Inf/negative zero
  showFloat′ : Float → String
  -- Float predicates
  isNaN′ : Float → Bool
  isInfinite′ : Float → Bool
  isNegativeZero′ : Float → Bool
  -- ByteString length
  byteStringLength : ByteString → ℕ
  -- Convert string to list of codepoints
  stringToCodepoints : String → List ℕ
  -- Read an environment variable
  lookupEnvVar : String → Prim.IO (Maybe String)
  -- String infix check
  isInfixOf′ : String → String → Bool

{-# COMPILE GHC showℤ = T.pack . show    #-}
{-# COMPILE GHC showFloat′ = \d -> T.pack (showDouble' d)
  where
    showDouble' d
      | isNaN d = "NaN"
      | isInfinite d = if d > 0 then "Infinity" else "-Infinity"
      | d == 0 && isNegativeZero d = "-0.0"
      | otherwise = show d
  #-}
{-# COMPILE GHC isNaN′          = isNaN          #-}
{-# COMPILE GHC isInfinite′     = isInfinite     #-}
{-# COMPILE GHC isNegativeZero′ = isNegativeZero #-}
{-# COMPILE GHC byteStringLength = fromIntegral . BS.length #-}
{-# COMPILE GHC stringToCodepoints = map (fromIntegral . ord) . T.unpack #-}
{-# COMPILE GHC lookupEnvVar = \k -> fmap (fmap T.pack) (lookupEnv (T.unpack k)) #-}
{-# COMPILE GHC isInfixOf′ = \needle haystack -> T.isInfixOf needle haystack #-}

-- ============================================================================
-- Pure Agda helper functions
-- ============================================================================

-- Extract Bool from Maybe Bool with default
fromMaybeBool : Bool → Maybe Bool → Bool
fromMaybeBool def nothing  = def
fromMaybeBool _   (just x) = x

-- Extract ℕ from Maybe ℤ with default
fromMaybeℤtoℕ : ℕ → Maybe ℤ → ℕ
fromMaybeℤtoℕ def nothing  = def
fromMaybeℤtoℕ _   (just x) = ℤ.∣ x ∣

-- Show a list of ℕ as JSON array: "[1,2,3]"
showNatListJson : List ℕ → String
showNatListJson ns = "[" ++ go ns ++ "]"
  where
    showNat : ℕ → String
    showNat n = showℤ (+ n)
    go : List ℕ → String
    go []       = ""
    go (x ∷ []) = showNat x
    go (x ∷ xs) = showNat x ++ "," ++ go xs

-- Show a list of ℤ as JSON array: "[1,-2,3]"
showIntListJson : List ℤ → String
showIntListJson ns = "[" ++ go ns ++ "]"
  where
    go : List ℤ → String
    go []       = ""
    go (x ∷ []) = showℤ x
    go (x ∷ xs) = showℤ x ++ "," ++ go xs

-- Format a float as conformance JSON
floatToJson : Float → String
floatToJson d with isNaN′ d
... | true  = "{\"is_nan\": true}"
... | false with isInfinite′ d
...   | true  = "{\"is_infinite\": true}"
...   | false = "{\"value\": " ++ showFloat′ d ++ "}"
