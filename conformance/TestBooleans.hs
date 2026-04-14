{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR

main :: IO ()
main = runConformance $ \tc _params writer -> do
  val <- generate tc $ cborMap [(cborText "type", cborText "boolean")]
  case termToBool val of
    Just True  -> writer "{\"value\": true}"
    Just False -> writer "{\"value\": false}"
    Nothing    -> writer "{\"value\": null}"
