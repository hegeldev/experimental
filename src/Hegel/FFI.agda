module Hegel.FFI where

open import Level using (Level; 0ℓ)
open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ)
open import Data.Integer.Base using (ℤ)
open import Data.Float.Base using (Float)
open import Data.String.Base using (String)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO)

-- ============================================================================
-- Pair type for FFI (avoids Σ which lacks a COMPILE GHC pragma)
-- ============================================================================

data Pair (A B : Set) : Set where
  pair : A → B → Pair A B

{-# FOREIGN GHC type AgdaPair a b = (a, b) #-}
{-# COMPILE GHC Pair = data AgdaPair ((,)) #-}

fst : {A B : Set} → Pair A B → A
fst (pair a _) = a

snd : {A B : Set} → Pair A B → B
snd (pair _ b) = b

{-# FOREIGN GHC
import qualified HegelFFI as H
import qualified Codec.CBOR.Term as CBOR
import qualified Data.ByteString as BS
import Data.Text (pack, unpack)
#-}

-- ============================================================================
-- Opaque types from Haskell
-- ============================================================================

postulate
  TestCase   : Set
  Value      : Set
  ByteString : Set

{-# COMPILE GHC TestCase   = type H.TestCase   #-}
{-# COMPILE GHC Value      = type CBOR.Term     #-}
{-# COMPILE GHC ByteString = type BS.ByteString #-}

-- ============================================================================
-- Core generation operations
-- ============================================================================

postulate
  generateFromSchema : TestCase → Value → Prim.IO Value
  startSpan          : TestCase → ℕ → Prim.IO ⊤
  stopSpan           : TestCase → Bool → Prim.IO ⊤
  newCollection      : TestCase → ℕ → Maybe ℕ → Prim.IO ⊤
  collectionMore     : TestCase → Prim.IO Bool
  collectionReject   : TestCase → Prim.IO ⊤

{-# COMPILE GHC generateFromSchema = \tc s -> H.generate tc s #-}
{-# COMPILE GHC startSpan          = \tc l -> H.startSpan tc (fromIntegral l)  #-}
{-# COMPILE GHC stopSpan           = \tc d -> H.stopSpan tc d #-}
{-# COMPILE GHC newCollection      = \tc mn mx -> H.newCollection tc (fromIntegral mn) (fmap fromIntegral mx) #-}
{-# COMPILE GHC collectionMore     = \tc -> H.collectionMore tc #-}
{-# COMPILE GHC collectionReject   = \tc -> H.collectionReject tc #-}

-- ============================================================================
-- Control functions
-- ============================================================================

postulate
  assume : TestCase → Bool → Prim.IO ⊤
  note   : TestCase → String → Prim.IO ⊤
  target : TestCase → Float → String → Prim.IO ⊤

{-# COMPILE GHC assume = \tc b -> H.hegelAssume tc b #-}
{-# COMPILE GHC note   = \tc m -> H.hegelNote tc (unpack m)   #-}
{-# COMPILE GHC target = \tc v l -> H.hegelTarget tc v (unpack l) #-}

-- ============================================================================
-- CBOR value construction (using Pair for FFI boundary)
-- ============================================================================

postulate
  cborMap    : List (Pair Value Value) → Value
  cborText   : String → Value
  cborInt    : ℤ → Value
  cborFloat  : Float → Value
  cborBool   : Bool → Value
  cborNull   : Value
  cborList   : List Value → Value
  cborBytes  : ByteString → Value

{-# COMPILE GHC cborMap   = \pairs -> H.cborMap pairs #-}
{-# COMPILE GHC cborText  = \s -> H.cborText (unpack s) #-}
{-# COMPILE GHC cborInt   = \n -> H.cborInt (fromIntegral n) #-}
{-# COMPILE GHC cborFloat = \f -> H.cborFloat f                 #-}
{-# COMPILE GHC cborBool  = \b -> H.cborBool b                  #-}
{-# COMPILE GHC cborNull  = H.cborNull                          #-}
{-# COMPILE GHC cborList  = \l -> H.cborList l                  #-}
{-# COMPILE GHC cborBytes = \b -> H.cborBytes b                 #-}

-- Convenience: make a key-value pair for schema maps
_,ᵥ_ : Value → Value → Pair Value Value
_,ᵥ_ = pair

infixr 4 _,ᵥ_

-- ============================================================================
-- CBOR value deconstruction
-- ============================================================================

postulate
  valueToInt    : Value → Maybe ℤ
  valueToFloat  : Value → Maybe Float
  valueToBool   : Value → Maybe Bool
  valueToText   : Value → Maybe String
  valueToBytes  : Value → Maybe ByteString
  valueToList   : Value → Maybe (List Value)

{-# COMPILE GHC valueToInt   = \v -> fmap fromIntegral (H.termToInt v)    #-}
{-# COMPILE GHC valueToFloat = \v -> H.termToDouble v                     #-}
{-# COMPILE GHC valueToBool  = \v -> H.termToBool v                       #-}
{-# COMPILE GHC valueToText  = \v -> fmap pack (H.termToText v)           #-}
{-# COMPILE GHC valueToBytes = \v -> H.termToBytes v                      #-}
{-# COMPILE GHC valueToList  = \v -> H.termToList v                       #-}

-- ============================================================================
-- Test runner (using Pair for named test list)
-- ============================================================================

postulate
  runHegelTest  : String → (TestCase → Prim.IO ⊤) → Prim.IO Bool
  runHegelTests : List (Pair String (TestCase → Prim.IO ⊤)) → Prim.IO Bool

{-# COMPILE GHC runHegelTest  = \name fn -> H.runHegelTest H.defaultSettings (unpack name) fn #-}
{-# COMPILE GHC runHegelTests = \tests -> H.runHegelTests H.defaultSettings (map (\(n, f) -> (unpack n, f)) tests) #-}
