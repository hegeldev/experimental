module TestBooleans where

open import Data.Bool.Base using (Bool; true; false)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  draw tc booleans Prim.>>= λ b →
  writeResult writer (boolToJson b) Prim.>>= λ _ →
  Prim.pure tt
  where
    boolToJson : Bool → _
    boolToJson true  = "{\"value\": true}"
    boolToJson false = "{\"value\": false}"
