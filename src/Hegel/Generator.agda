module Hegel.Generator where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ; zero; suc)
open import Data.Unit.Base using (⊤; tt)
open import Function.Base using (_∘_; id)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI

-- ============================================================================
-- BasicGenerator: schema-based, single-request generation
-- ============================================================================

record BasicGenerator (A : Set) : Set where
  constructor mkBasicGen
  field
    schema    : Value
    transform : Value → A

mapBasic : {A B : Set} → (A → B) → BasicGenerator A → BasicGenerator B
mapBasic f bg = mkBasicGen (BasicGenerator.schema bg) (f ∘ BasicGenerator.transform bg)

-- ============================================================================
-- Generator: the user-facing generator type
-- ============================================================================

record Generator (A : Set) : Set where
  constructor mkGen
  field
    generate : TestCase → Prim.IO A
    asBasic  : Maybe (BasicGenerator A)

-- ============================================================================
-- Constructing Generators
-- ============================================================================

-- Draw from a BasicGenerator: send schema, apply transform
drawBasic : {A : Set} → TestCase → BasicGenerator A → Prim.IO A
drawBasic tc bg =
  generateFromSchema tc (BasicGenerator.schema bg) Prim.>>= λ raw →
  Prim.pure (BasicGenerator.transform bg raw)

-- Lift a BasicGenerator to a Generator
fromBasic : {A : Set} → BasicGenerator A → Generator A
fromBasic bg = mkGen (λ tc → drawBasic tc bg) (just bg)

-- Create a composite (non-basic) generator
composite : {A : Set} → (TestCase → Prim.IO A) → Generator A
composite f = mkGen f nothing

-- ============================================================================
-- Span labels (matching the Hegel protocol)
-- ============================================================================

module Labels where
  LIST         = 1
  LIST-ELEMENT = 2
  SET          = 3
  SET-ELEMENT  = 4
  MAP          = 5
  MAP-ENTRY    = 6
  TUPLE        = 7
  ONE-OF       = 8
  OPTIONAL     = 9
  FIXED-DICT   = 10
  FLAT-MAP     = 11
  FILTER       = 12
  MAPPED       = 13
  SAMPLED-FROM = 14

-- ============================================================================
-- Core operation: draw
-- ============================================================================

draw : {A : Set} → TestCase → Generator A → Prim.IO A
draw tc gen = Generator.generate gen tc
