module TestBinary where

open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.Maybe.Base as Maybe using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  let opts = mkBinaryOpts
        (fromMaybeℤtoℕ 0 (getParamInt "min_size" params))
        (Maybe.map ℤ.∣_∣ (getParamInt "max_size" params))
      gen = binaryWith opts
  in
  draw tc gen Prim.>>= λ bs →
  writeResult writer ("{\"length\": " ++ showℤ (+ byteStringLength bs) ++ "}") Prim.>>= λ _ →
  Prim.pure tt
