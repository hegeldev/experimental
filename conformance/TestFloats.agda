module TestFloats where

open import Data.Bool.Base using (Bool; false)
open import Data.Float.Base using (Float)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  let opts = mkFloatOpts
        (getParamFloat "min_value" params)
        (getParamFloat "max_value" params)
        (getParamBool "allow_nan" params)
        (getParamBool "allow_infinity" params)
        (fromMaybeBool false (getParamBool "exclude_min" params))
        (fromMaybeBool false (getParamBool "exclude_max" params))
      gen = floatsWith opts
  in
  draw tc gen Prim.>>= λ d →
  writeResult writer (floatToJson d) Prim.>>= λ _ →
  Prim.pure tt
