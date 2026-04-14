module TestSampledFrom where

open import Data.Integer.Base using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  let options = fromMaybeIntList ((+ 1) ∷ (+ 2) ∷ (+ 3) ∷ [])
                  (getParamIntList "options" params)
      gen = sampledFrom options
  in
  draw tc gen Prim.>>= λ v →
  writeResult writer ("{\"value\": " ++ showℤ v ++ "}") Prim.>>= λ _ →
  Prim.pure tt
  where
    fromMaybeIntList : List ℤ → Maybe (List ℤ) → List ℤ
    fromMaybeIntList def nothing  = def
    fromMaybeIntList _   (just x) = x
