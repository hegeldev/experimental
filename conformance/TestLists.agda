module TestLists where

open import Data.Bool.Base using (Bool; true; false)
open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base as Maybe using (Maybe; just; nothing)
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
      unique′ = getParamBool "unique" params
      elemGen = integersWith (mkIntOpts
                  (getParamInt "min_value" params)
                  (getParamInt "max_value" params))
  in
  drawList mode minSz maxSz unique′ elemGen tc Prim.>>= λ elems →
  writeResult writer ("{\"elements\": " ++ showIntListJson elems ++ "}") Prim.>>= λ _ →
  Prim.pure tt
  where
    isNonBasic : Maybe String → Bool
    isNonBasic (just "non_basic") = true
    isNonBasic _                  = false

    drawList : Maybe String → _ → _ → _ → Generator ℤ → TestCase → Prim.IO (List ℤ)
    drawList mode minSz maxSz unique′ elemGen tc with isNonBasic mode
    -- Non-basic: wrap the element generator as composite to force collection protocol
    ... | true =
      let nonBasicElem = composite (λ tc′ → draw tc′ elemGen)
          opts = mkListOpts minSz maxSz nothing
      in draw tc (listsWith opts nonBasicElem)
    -- Basic: use schema composition
    ... | false =
      let opts = mkListOpts minSz maxSz unique′
      in draw tc (listsWith opts elemGen)
