{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR

main :: IO ()
main = runConformance $ \tc params writer -> do
  let schema = cborMap $
        [(cborText "type", cborText "integer")]
        ++ maybe [] (\v -> [(cborText "min_value", cborInt (fromIntegral v))]) (paramInt "min_value" params)
        ++ maybe [] (\v -> [(cborText "max_value", cborInt (fromIntegral v))]) (paramInt "max_value" params)
  val <- generate tc schema
  case termToInt val of
    Just n  -> writer $ "{\"value\": " ++ show n ++ "}"
    Nothing -> writer "{\"value\": 0}"
