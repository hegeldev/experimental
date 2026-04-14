module Hegel.Combinators where

open import Data.Bool.Base using (Bool; true; false; if_then_else_)
open import Data.List.Base using (List; []; _∷_; length)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ; zero; suc; _∸_)
open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.Unit.Base using (⊤; tt)
open import Function.Base using (_∘_; id)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel.FFI
open import Hegel.Generator

-- ============================================================================
-- map: preserves basicness when source is basic
-- ============================================================================

gmap : {A B : Set} → (A → B) → Generator A → Generator B
gmap {A} {B} f gen with Generator.asBasic gen
... | just bg = fromBasic (mapBasic f bg)
... | nothing = composite (λ tc →
  startSpan tc Labels.MAPPED Prim.>>= λ _ →
  Generator.generate gen tc Prim.>>= λ a →
  stopSpan tc false Prim.>>= λ _ →
  Prim.pure (f a))

-- ============================================================================
-- filter: always produces a composite generator (3 retries)
-- ============================================================================

gfilter : {A : Set} → (A → Bool) → Generator A → Generator A
gfilter {A} pred gen = composite (λ tc → tryFilter tc 3)
  where
    finish : Bool → TestCase → A → Prim.IO (Maybe A)
    finish true  tc a = stopSpan tc false Prim.>>= λ _ → Prim.pure (just a)
    finish false tc a = stopSpan tc true  Prim.>>= λ _ → Prim.pure nothing

    tryOnce : TestCase → Prim.IO (Maybe A)
    tryOnce tc =
      startSpan tc Labels.FILTER Prim.>>= λ _ →
      Generator.generate gen tc Prim.>>= λ a →
      finish (pred a) tc a

    tryFilter : TestCase → ℕ → Prim.IO A
    tryFilter tc zero =
      assume tc false Prim.>>= λ _ →
      Generator.generate gen tc  -- unreachable; assume false throws
    tryFilter tc (suc n) =
      tryOnce tc Prim.>>= λ where
        (just a) → Prim.pure a
        nothing  → tryFilter tc n

-- ============================================================================
-- flatMap: always produces a composite generator
-- ============================================================================

flatMap : {A B : Set} → Generator A → (A → Generator B) → Generator B
flatMap genA f = composite (λ tc →
  startSpan tc Labels.FLAT-MAP Prim.>>= λ _ →
  Generator.generate genA tc Prim.>>= λ a →
  Generator.generate (f a) tc Prim.>>= λ b →
  stopSpan tc false Prim.>>= λ _ →
  Prim.pure b)

-- ============================================================================
-- oneOf: basic if all branches have basic reps with no transforms,
--        otherwise composite
-- ============================================================================

-- For simplicity, we always use the composite path for oneOf.
-- The basic optimization can be added later.
oneOf : {A : Set} → List (Generator A) → Generator A
oneOf {A} gens = composite (λ tc →
  startSpan tc Labels.ONE-OF Prim.>>= λ _ →
  let indexSchema = cborMap
        ( (cborText "type"      ,ᵥ cborText "integer")
        ∷ (cborText "min_value" ,ᵥ cborInt (+ 0))
        ∷ (cborText "max_value" ,ᵥ cborInt (+ (length gens ∸ 1)))
        ∷ []) in
  generateFromSchema tc indexSchema Prim.>>= λ idxV →
  let idx = intToNat (valueToInt idxV) in
  drawNth tc gens idx Prim.>>= λ result →
  stopSpan tc false Prim.>>= λ _ →
  Prim.pure result)
  where
    intToNat : Maybe ℤ → ℕ
    intToNat nothing  = 0
    intToNat (just x) = ℤ.∣ x ∣

    drawNth : TestCase → List (Generator A) → ℕ → Prim.IO A
    drawNth tc (g ∷ _)  zero    = Generator.generate g tc
    drawNth tc (_ ∷ gs) (suc n) = drawNth tc gs n
    drawNth tc []       _       = assume tc false Prim.>>= λ _ →
                                  Generator.generate (composite (λ _ → Prim.pure tt')) tc
      where postulate tt' : A

-- ============================================================================
-- optional: generate Nothing or Just a
-- ============================================================================

optional : {A : Set} → Generator A → Generator (Maybe A)
optional gen = oneOf
  ( composite (λ _ → Prim.pure nothing)
  ∷ gmap just gen
  ∷ [])
