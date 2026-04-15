{-
  FFI Design Sketch: How Agda talks to the Haskell protocol layer.

  The strategy:
  1. Write a Haskell module (HegelFFI.hs) that implements the protocol.
  2. Use Agda's {-# FOREIGN GHC #-} and postulate mechanism to bind Agda
     types and functions to the Haskell implementations.
  3. The Haskell module handles: subprocess management, CBOR encoding/decoding,
     wire protocol (20-byte header, CRC32), stream multiplexing, and RPC.
  4. Agda handles: Generator types, combinators, schema composition,
     basic/composite distinction, and the user-facing API.

  The boundary is at the "generate a value given a schema" level:
  - Agda composes schemas and transforms (generator logic)
  - Haskell sends schemas over the wire and returns raw CBOR values
-}

module sketches.FFI-Design where

-- =============================================================================
-- Step 1: Haskell types bound to Agda
-- =============================================================================

{-# FOREIGN GHC
import qualified HegelFFI as H
import qualified Data.ByteString as BS
import qualified Codec.CBOR.Term as CBOR
#-}

-- Opaque Haskell types
postulate
  TestCase   : Set
  Value      : Set     -- CBOR.Term
  ByteString : Set

{-# COMPILE GHC TestCase   = type H.TestCase   #-}
{-# COMPILE GHC Value      = type CBOR.Term     #-}
{-# COMPILE GHC ByteString = type BS.ByteString #-}

-- =============================================================================
-- Step 2: Primitive FFI operations
-- =============================================================================

-- These are the minimal set of Haskell functions Agda needs:

postulate
  -- Connection lifecycle
  withHegelServer : {A : Set} → (TestCase → IO A) → IO A

  -- Core generation: send schema, get value
  generateFromSchema : TestCase → Value → IO Value

  -- Spans for composite generation
  startSpan : TestCase → ℕ → IO ⊤      -- label (ℕ from SpanLabel enum)
  stopSpan  : TestCase → Bool → IO ⊤    -- discard flag

  -- Collections protocol
  newCollection  : TestCase → ℕ → Maybe ℕ → IO ⊤   -- min, max
  collectionMore : TestCase → IO Bool
  collectionReject : TestCase → IO ⊤

  -- Control
  hegelAssume : TestCase → Bool → IO ⊤
  hegelNote   : TestCase → String → IO ⊤
  hegelTarget : TestCase → Float → String → IO ⊤

  -- Test lifecycle
  markComplete : TestCase → ℕ → IO ⊤   -- status: 0=valid, 1=invalid, 2=interesting

  -- CBOR construction helpers (for building schemas in Agda)
  cborMap     : List (String × Value) → Value
  cborString  : String → Value
  cborInt     : ℤ → Value
  cborFloat   : Float → Value
  cborBool    : Bool → Value
  cborNull    : Value
  cborList    : List Value → Value

  -- CBOR deconstruction helpers (for parsing server responses in Agda)
  valueToInt    : Value → Maybe ℤ
  valueToFloat  : Value → Maybe Float
  valueToBool   : Value → Maybe Bool
  valueToString : Value → Maybe String
  valueToBytes  : Value → Maybe ByteString
  valueToList   : Value → Maybe (List Value)
  valueToMap    : Value → Maybe (List (Value × Value))

{-# COMPILE GHC withHegelServer    = H.withHegelServer    #-}
{-# COMPILE GHC generateFromSchema = H.generateFromSchema #-}
{-# COMPILE GHC startSpan          = H.startSpan          #-}
{-# COMPILE GHC stopSpan           = H.stopSpan           #-}
-- ... etc for all postulates

-- =============================================================================
-- Step 3: Schema construction in Agda
-- =============================================================================

-- Schemas are just CBOR Values, built using the helpers above.
-- This keeps schema logic in Agda where we can reason about it.

integerSchema : Maybe ℤ → Maybe ℤ → Value
integerSchema min max = cborMap (
  ("type" , cborString "integer")
  ∷ maybe [] (λ v → ("min_value" , cborInt v) ∷ []) min
  ++ maybe [] (λ v → ("max_value" , cborInt v) ∷ []) max )

booleanSchema : Value
booleanSchema = cborMap (("type" , cborString "boolean") ∷ [])

textSchema : ℕ → Maybe ℕ → Value
textSchema minSize maxSize = cborMap (
  ("type" , cborString "string")
  ∷ ("min_size" , cborInt (pos minSize))
  ∷ maybe [] (λ v → ("max_size" , cborInt (pos v)) ∷ []) maxSize )

-- =============================================================================
-- Step 4: Generator implementation in Agda (using FFI primitives)
-- =============================================================================

-- BasicGenerator: schema + transform, always single-request
record BasicGenerator (A : Set) : Set where
  field
    schema    : Value
    transform : Value → A

-- Generate from a BasicGenerator: send schema, apply transform
drawBasic : {A : Set} → TestCase → BasicGenerator A → IO A
drawBasic tc bg = do
  raw ← generateFromSchema tc (BasicGenerator.schema bg)
  return (BasicGenerator.transform bg raw)

-- map on BasicGenerator: compose transforms, keep schema
mapBasic : {A B : Set} → (A → B) → BasicGenerator A → BasicGenerator B
mapBasic f bg = record
  { schema    = BasicGenerator.schema bg
  ; transform = f ∘ BasicGenerator.transform bg
  }

-- Generator: can be basic or composite
record Generator (A : Set) : Set₁ where
  field
    generate : TestCase → IO A
    asBasic  : Maybe (BasicGenerator A)

-- Lift BasicGenerator to Generator
fromBasic : {A : Set} → BasicGenerator A → Generator A
fromBasic bg = record
  { generate = λ tc → drawBasic tc bg
  ; asBasic  = just bg
  }

-- Example: integers generator
integers : Generator ℤ
integers = fromBasic (record
  { schema    = integerSchema nothing nothing
  ; transform = λ v → fromMaybe 0 (valueToInt v)
  })

integersIn : ℤ → ℤ → Generator ℤ
integersIn lo hi = fromBasic (record
  { schema    = integerSchema (just lo) (just hi)
  ; transform = λ v → fromMaybe 0 (valueToInt v)
  })

-- map on Generator: preserves basicness
gmap : {A B : Set} → (A → B) → Generator A → Generator B
gmap f gen with Generator.asBasic gen
... | just bg = fromBasic (mapBasic f bg)
... | nothing = record
  { generate = λ tc → do
      a ← Generator.generate gen tc
      return (f a)
  ; asBasic = nothing
  }

-- =============================================================================
-- Step 5: The draw function
-- =============================================================================

draw : {A : Set} → TestCase → Generator A → IO A
draw tc gen = Generator.generate gen tc
