module Hegel.Generators.Primitives where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_; length; map)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ; zero; suc; _∸_)
open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.Float.Base using (Float)
open import Data.String.Base using (String)
open import Data.Unit.Base using (⊤; tt)
open import Function.Base using (_∘_; id; const)
open import IO.Primitive.Core as Prim using (IO)

open import Hegel.FFI
open import Hegel.Generator

-- ============================================================================
-- Schema construction helpers
-- ============================================================================

addOpt : String → Maybe Value → List (Pair Value Value) → List (Pair Value Value)
addOpt _ nothing  fields = fields
addOpt k (just v) fields = (cborText k ,ᵥ v) ∷ fields

-- ============================================================================
-- Integers
-- ============================================================================

record IntegerOpts : Set where
  constructor mkIntOpts
  field
    minValue : Maybe ℤ
    maxValue : Maybe ℤ

defaultIntOpts : IntegerOpts
defaultIntOpts = mkIntOpts nothing nothing

integerSchema : IntegerOpts → Value
integerSchema opts = cborMap fields
  where
    open IntegerOpts opts
    fields = (cborText "type" ,ᵥ cborText "integer")
           ∷ addOpt "min_value" (Data.Maybe.Base.map cborInt minValue)
             (addOpt "max_value" (Data.Maybe.Base.map cborInt maxValue) [])

parseInt : Value → ℤ
parseInt v with valueToInt v
... | just n  = n
... | nothing = + 0

integers : Generator ℤ
integers = fromBasic (mkBasicGen (integerSchema defaultIntOpts) parseInt)

integersWith : IntegerOpts → Generator ℤ
integersWith opts = fromBasic (mkBasicGen (integerSchema opts) parseInt)

integersIn : ℤ → ℤ → Generator ℤ
integersIn lo hi = integersWith (mkIntOpts (just lo) (just hi))

-- ============================================================================
-- Floats
-- ============================================================================

record FloatOpts : Set where
  constructor mkFloatOpts
  field
    minValue      : Maybe Float
    maxValue      : Maybe Float
    allowNaN      : Maybe Bool
    allowInfinity : Maybe Bool
    excludeMin    : Bool
    excludeMax    : Bool

defaultFloatOpts : FloatOpts
defaultFloatOpts = mkFloatOpts nothing nothing nothing nothing false false

floatSchema : FloatOpts → Value
floatSchema opts = cborMap fields
  where
    open FloatOpts opts
    fields = (cborText "type" ,ᵥ cborText "float")
           ∷ addOpt "min_value" (Data.Maybe.Base.map cborFloat minValue)
             (addOpt "max_value" (Data.Maybe.Base.map cborFloat maxValue)
             (addOpt "allow_nan" (Data.Maybe.Base.map cborBool allowNaN)
             (addOpt "allow_infinity" (Data.Maybe.Base.map cborBool allowInfinity)
             ((cborText "exclude_min" ,ᵥ cborBool excludeMin)
           ∷ (cborText "exclude_max" ,ᵥ cborBool excludeMax)
           ∷ []))))

parseFloat : Value → Float
parseFloat v with valueToFloat v
... | just f  = f
... | nothing = 0.0

floats : Generator Float
floats = fromBasic (mkBasicGen (floatSchema defaultFloatOpts) parseFloat)

floatsWith : FloatOpts → Generator Float
floatsWith opts = fromBasic (mkBasicGen (floatSchema opts) parseFloat)

-- ============================================================================
-- Booleans
-- ============================================================================

parseBool : Value → Bool
parseBool v with valueToBool v
... | just b  = b
... | nothing = false

booleans : Generator Bool
booleans = fromBasic (mkBasicGen (cborMap ((cborText "type" ,ᵥ cborText "boolean") ∷ [])) parseBool)

-- ============================================================================
-- Text
-- ============================================================================

record TextOpts : Set where
  constructor mkTextOpts
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultTextOpts : TextOpts
defaultTextOpts = mkTextOpts 0 nothing

textSchema : TextOpts → Value
textSchema opts = cborMap fields
  where
    open TextOpts opts
    fields = (cborText "type" ,ᵥ cborText "string")
           ∷ (cborText "min_size" ,ᵥ cborInt (+ minSize))
           ∷ addOpt "max_size" (Data.Maybe.Base.map (cborInt ∘ +_) maxSize) []

parseText : Value → String
parseText v with valueToText v
... | just s  = s
... | nothing = ""

text : Generator String
text = fromBasic (mkBasicGen (textSchema defaultTextOpts) parseText)

textWith : TextOpts → Generator String
textWith opts = fromBasic (mkBasicGen (textSchema opts) parseText)

-- ============================================================================
-- Binary
-- ============================================================================

record BinaryOpts : Set where
  constructor mkBinaryOpts
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultBinaryOpts : BinaryOpts
defaultBinaryOpts = mkBinaryOpts 0 nothing

binarySchema : BinaryOpts → Value
binarySchema opts = cborMap fields
  where
    open BinaryOpts opts
    fields = (cborText "type" ,ᵥ cborText "binary")
           ∷ (cborText "min_size" ,ᵥ cborInt (+ minSize))
           ∷ addOpt "max_size" (Data.Maybe.Base.map (cborInt ∘ +_) maxSize) []

parseBytes : Value → ByteString
parseBytes v with valueToBytes v
... | just bs = bs
... | nothing = emptyBS
  where postulate emptyBS : ByteString

binary : Generator ByteString
binary = fromBasic (mkBasicGen (binarySchema defaultBinaryOpts) parseBytes)

binaryWith : BinaryOpts → Generator ByteString
binaryWith opts = fromBasic (mkBasicGen (binarySchema opts) parseBytes)

-- ============================================================================
-- just (constant value)
-- ============================================================================

justGen : {A : Set} → A → Generator A
justGen a = fromBasic (mkBasicGen schema (const a))
  where
    schema = cborMap
      ( (cborText "type"  ,ᵥ cborText "constant")
      ∷ (cborText "value" ,ᵥ cborNull) ∷ [])

-- ============================================================================
-- sampledFrom
-- ============================================================================

sampledFrom : {A : Set} → List A → Generator A
sampledFrom {A} [] = justGen a where postulate a : A
sampledFrom {A} vals@(v₀ ∷ _) = fromBasic (mkBasicGen schema transform)
  where
    schema = cborMap
      ( (cborText "type"      ,ᵥ cborText "integer")
      ∷ (cborText "min_value" ,ᵥ cborInt (+ 0))
      ∷ (cborText "max_value" ,ᵥ cborInt (+ (length vals ∸ 1))) ∷ [])
    nth : List A → ℕ → A
    nth []       _       = v₀
    nth (x ∷ _)  zero    = x
    nth (_ ∷ xs) (suc n) = nth xs n
    intToNat : Maybe ℤ → ℕ
    intToNat nothing  = 0
    intToNat (just x) = ℤ.∣ x ∣
    transform : Value → A
    transform v = nth vals (intToNat (valueToInt v))
