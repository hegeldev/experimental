module TestDicts where

open import Data.Bool.Base using (Bool; true; false)
open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_; length; map)
open import Data.Maybe.Base as Maybe using (Maybe; just; nothing)
open import Data.Product.Base using (_×_; _,_; proj₁; proj₂)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  let mode = getParamString "mode" params
      minSz = fromMaybeℤtoℕ 0 (getParamInt "min_size" params)
      maxSz = Maybe.map ℤ.∣_∣ (getParamInt "max_size" params)
      keyGen = integersWith (mkIntOpts
                 (getParamInt "min_key" params)
                 (getParamInt "max_key" params))
      valGen = integersWith (mkIntOpts
                 (getParamInt "min_value" params)
                 (getParamInt "max_value" params))
  in
  drawDict mode minSz maxSz keyGen valGen tc Prim.>>= λ kvs →
  let keys = map proj₁ kvs
      vals = map proj₂ kvs
      size = length kvs
  in
  writeResult writer (formatOutput size keys vals) Prim.>>= λ _ →
  Prim.pure tt
  where
    isNonBasic : Maybe String → Bool
    isNonBasic (just "non_basic") = true
    isNonBasic _                  = false

    drawDict : Maybe String → _ → _ → Generator ℤ → Generator ℤ → TestCase → Prim.IO (List (ℤ × ℤ))
    drawDict mode minSz maxSz keyGen valGen tc with isNonBasic mode
    ... | true =
      let nonBasicK = composite (λ tc′ → draw tc′ keyGen)
          nonBasicV = composite (λ tc′ → draw tc′ valGen)
          opts = mkDictOpts minSz maxSz
      in draw tc (dictsWith opts nonBasicK nonBasicV)
    ... | false =
      let opts = mkDictOpts minSz maxSz
      in draw tc (dictsWith opts keyGen valGen)

    minOf : List ℤ → ℤ
    minOf []       = + 0
    minOf (x ∷ xs) = go x xs
      where
        go : ℤ → List ℤ → ℤ
        go acc []       = acc
        go acc (y ∷ ys) with ℤ._≤ᵇ_ y acc
        ... | true  = go y ys
        ... | false = go acc ys

    maxOf : List ℤ → ℤ
    maxOf []       = + 0
    maxOf (x ∷ xs) = go x xs
      where
        go : ℤ → List ℤ → ℤ
        go acc []       = acc
        go acc (y ∷ ys) with ℤ._≤ᵇ_ acc y
        ... | true  = go y ys
        ... | false = go acc ys

    formatOutput : _ → List ℤ → List ℤ → String
    formatOutput size keys vals =
      "{\"size\": " ++ showℤ (+ size)
      ++ ", \"min_key\": " ++ showℤ (minOf keys)
      ++ ", \"max_key\": " ++ showℤ (maxOf keys)
      ++ ", \"min_value\": " ++ showℤ (minOf vals)
      ++ ", \"max_value\": " ++ showℤ (maxOf vals)
      ++ "}"
