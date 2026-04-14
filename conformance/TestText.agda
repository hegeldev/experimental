module TestText where

open import Data.Integer.Base as ℤ using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base as Maybe using (Maybe; just; nothing)
open import Data.Nat.Base using (ℕ)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.FFI using (generateFromSchema)
open import Hegel.Generator using (BasicGenerator; mkBasicGen)
open import Hegel.Conformance

main : Prim.IO ⊤
main = runConformance λ tc params writer →
  let opts = mkTextOpts
        (fromMaybeℤtoℕ 0 (getParamInt "min_size" params))
        (Maybe.map ℤ.∣_∣ (getParamInt "max_size" params))
        (getParamString "codec" params)
        (Maybe.map ℤ.∣_∣ (getParamInt "min_codepoint" params))
        (Maybe.map ℤ.∣_∣ (getParamInt "max_codepoint" params))
        (getParamStringList "categories" params)
        (getParamStringList "exclude_categories" params)
        (getParamString "include_characters" params)
        (getParamString "exclude_characters" params)
      gen = textWith opts
  in
  -- Use the generator's schema (verifying API schema construction)
  -- but extract raw codepoints to correctly handle WTF-8 surrogates
  -- which Data.Text would replace with U+FFFD.
  generateFromSchema tc (getSchema gen) Prim.>>= λ raw →
  let cps = fromMaybeCps (valueToCodepoints raw) in
  writeResult writer ("{\"codepoints\": " ++ showNatListJson cps ++ "}") Prim.>>= λ _ →
  Prim.pure tt
  where
    getSchema : Generator String → Hegel.FFI.Value
    getSchema g with Generator.asBasic g
    ... | just bg = BasicGenerator.schema bg
    ... | nothing = Hegel.FFI.cborNull

    fromMaybeCps : Maybe (List ℕ) → List ℕ
    fromMaybeCps nothing   = []
    fromMaybeCps (just cs) = cs
