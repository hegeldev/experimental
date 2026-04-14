module TestIntegers where

open import Data.Integer.Base using (ℤ)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  let gen = integersWith (mkIntOpts
              (getParamInt "min_value" params)
              (getParamInt "max_value" params))
  in
  draw tc gen Prim.>>= λ n →
  writeResult writer ("{\"value\": " ++ showℤ n ++ "}") Prim.>>= λ _ →
  Prim.pure tt
