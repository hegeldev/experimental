module TestErrorHandling where

open import Data.Bool.Base using (Bool; true; false)
open import Data.Integer.Base using (ℤ; +_)
open import Data.List.Base using (List; []; _∷_)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import IO.Primitive.Core as Prim using (IO; _>>=_; pure)

open import Hegel
open import Hegel.Conformance

main : Prim.IO ⊤
main =
  lookupEnvVar "HEGEL_PROTOCOL_TEST_MODE" Prim.>>= λ testMode →
  let isCollectionMode = checkCollectionMode testMode in
  runConformance λ tc params writer →
    runTest isCollectionMode tc Prim.>>= λ _ →
    writeResult writer "{}" Prim.>>= λ _ →
    Prim.pure tt
  where
    checkCollectionMode : Maybe String → Bool
    checkCollectionMode nothing  = false
    checkCollectionMode (just m) = isInfixOf′ "collection" m

    -- For collection modes, draw a list using the collection protocol
    -- (composite element generator forces collection protocol)
    runTest : Bool → TestCase → Prim.IO ⊤
    runTest true tc =
      let nonBasicInt = composite (λ tc′ →
            draw tc′ (integersIn (+ 0) (+ 100)))
          gen = listsWith (mkListOpts 0 (just 5) nothing) nonBasicInt
      in
      draw tc gen Prim.>>= λ _ →
      Prim.pure tt
    runTest false tc =
      draw tc booleans Prim.>>= λ _ →
      Prim.pure tt
