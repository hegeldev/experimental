module Hegel.Generators.Collections where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_; _++_; map)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ; zero; suc; _∸_)
open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.String.Base using (String)
open import Data.Product.Base using (_×_; _,_)
open import Data.Unit.Base using (⊤; tt)
open import Function.Base using (_∘_; id)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI
open import Hegel.Generator
open import Hegel.Generators.Primitives using (addOpt)

-- ============================================================================
-- Collection loop helpers (server-driven, terminate when collectionMore → false)
-- ============================================================================

-- These loops are driven by the hegel-core server's collection protocol.
-- They always terminate because the server eventually returns false from
-- collectionMore. Agda's termination checker can't see through IO, so
-- we mark them {-# TERMINATING #-}.

{-# TERMINATING #-}
collectList : {A : Set} → (TestCase → Prim.IO A) → TestCase → List A → Prim.IO (List A)
collectList genFn tc acc =
  collectionMore tc Prim.>>= λ where
    false → Prim.pure acc
    true  →
      startSpan tc Labels.LIST-ELEMENT Prim.>>= λ _ →
      genFn tc Prim.>>= λ elem →
      stopSpan tc false Prim.>>= λ _ →
      collectList genFn tc (acc ++ (elem ∷ []))

{-# TERMINATING #-}
collectDict : {K V : Set} → (TestCase → Prim.IO K) → (TestCase → Prim.IO V)
            → TestCase → List (K × V) → Prim.IO (List (K × V))
collectDict genK genV tc acc =
  collectionMore tc Prim.>>= λ where
    false → Prim.pure acc
    true  →
      startSpan tc Labels.MAP-ENTRY Prim.>>= λ _ →
      genK tc Prim.>>= λ k →
      genV tc Prim.>>= λ v →
      stopSpan tc false Prim.>>= λ _ →
      collectDict genK genV tc (acc ++ ((k , v) ∷ []))

-- ============================================================================
-- Lists
-- ============================================================================

record ListOpts : Set where
  constructor mkListOpts
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultListOpts : ListOpts
defaultListOpts = mkListOpts 0 nothing

lists : {A : Set} → Generator A → Generator (List A)
lists {A} elemGen with Generator.asBasic elemGen
... | just elemBg = fromBasic (mkBasicGen schema transform)
  where
    schema = cborMap
      ( (cborText "type"     ,ᵥ cborText "list")
      ∷ (cborText "elements" ,ᵥ BasicGenerator.schema elemBg)
      ∷ (cborText "min_size" ,ᵥ cborInt (+ 0))
      ∷ [])
    transform : Value → List A
    transform v with valueToList v
    ... | just vs = map (BasicGenerator.transform elemBg) vs
    ... | nothing = []
... | nothing = composite (λ tc →
    startSpan tc Labels.LIST Prim.>>= λ _ →
    newCollection tc 0 nothing Prim.>>= λ _ →
    collectList (Generator.generate elemGen) tc [] Prim.>>= λ result →
    stopSpan tc false Prim.>>= λ _ →
    Prim.pure result)

listsWith : {A : Set} → ListOpts → Generator A → Generator (List A)
listsWith {A} opts elemGen with Generator.asBasic elemGen
... | just elemBg = fromBasic (mkBasicGen schema transform)
  where
    open ListOpts opts
    schema = cborMap
      ( (cborText "type"     ,ᵥ cborText "list")
      ∷ (cborText "elements" ,ᵥ BasicGenerator.schema elemBg)
      ∷ (cborText "min_size" ,ᵥ cborInt (+ minSize))
      ∷ addOpt "max_size" (Data.Maybe.Base.map (cborInt ∘ +_) maxSize) [])
    transform : Value → List A
    transform v with valueToList v
    ... | just vs = map (BasicGenerator.transform elemBg) vs
    ... | nothing = []
... | nothing = composite (λ tc →
    let open ListOpts opts in
    startSpan tc Labels.LIST Prim.>>= λ _ →
    newCollection tc minSize maxSize Prim.>>= λ _ →
    collectList (Generator.generate elemGen) tc [] Prim.>>= λ result →
    stopSpan tc false Prim.>>= λ _ →
    Prim.pure result)

-- ============================================================================
-- Tuples (pairs)
-- ============================================================================

tuples : {A B : Set} → Generator A → Generator B → Generator (A × B)
tuples {A} {B} genA genB with Generator.asBasic genA | Generator.asBasic genB
... | just bgA | just bgB = fromBasic (mkBasicGen schema transform)
  where
    schema = cborMap
      ( (cborText "type"     ,ᵥ cborText "tuple")
      ∷ (cborText "elements" ,ᵥ cborList
          (BasicGenerator.schema bgA ∷ BasicGenerator.schema bgB ∷ []))
      ∷ [])
    transform : Value → A × B
    transform v with valueToList v
    ... | just (va ∷ vb ∷ _) =
      BasicGenerator.transform bgA va , BasicGenerator.transform bgB vb
    ... | _ = BasicGenerator.transform bgA v , BasicGenerator.transform bgB v
... | _ | _ = composite (λ tc →
    startSpan tc Labels.TUPLE Prim.>>= λ _ →
    Generator.generate genA tc Prim.>>= λ a →
    Generator.generate genB tc Prim.>>= λ b →
    stopSpan tc false Prim.>>= λ _ →
    Prim.pure (a , b))

-- ============================================================================
-- Dicts (as lists of key-value pairs)
-- ============================================================================

record DictOpts : Set where
  constructor mkDictOpts
  field
    minSize : ℕ
    maxSize : Maybe ℕ

defaultDictOpts : DictOpts
defaultDictOpts = mkDictOpts 0 nothing

dicts : {K V : Set} → Generator K → Generator V → Generator (List (K × V))
dicts {K} {V} keyGen valGen with Generator.asBasic keyGen | Generator.asBasic valGen
... | just bgK | just bgV = fromBasic (mkBasicGen schema transform)
  where
    schema = cborMap
      ( (cborText "type"   ,ᵥ cborText "dict")
      ∷ (cborText "keys"   ,ᵥ BasicGenerator.schema bgK)
      ∷ (cborText "values" ,ᵥ BasicGenerator.schema bgV)
      ∷ (cborText "min_size" ,ᵥ cborInt (+ 0))
      ∷ [])
    parsePair : Value → K × V
    parsePair v with valueToList v
    ... | just (kv ∷ vv ∷ _) = BasicGenerator.transform bgK kv , BasicGenerator.transform bgV vv
    ... | _ = BasicGenerator.transform bgK v , BasicGenerator.transform bgV v
    transform : Value → List (K × V)
    transform v with valueToList v
    ... | just pairs = map parsePair pairs
    ... | nothing    = []
... | _ | _ = composite (λ tc →
    startSpan tc Labels.MAP Prim.>>= λ _ →
    newCollection tc 0 nothing Prim.>>= λ _ →
    collectDict (Generator.generate keyGen) (Generator.generate valGen) tc [] Prim.>>= λ result →
    stopSpan tc false Prim.>>= λ _ →
    Prim.pure result)
