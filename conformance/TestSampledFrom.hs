{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR

main :: IO ()
main = runConformance $ \tc params writer -> do
  let options = maybe [1, 2, 3] id (paramIntList "options" params)
      nOpts = length options
      schema = cborMap
        [ (cborText "type", cborText "integer")
        , (cborText "min_value", cborInt 0)
        , (cborText "max_value", cborInt (fromIntegral (nOpts - 1)))
        ]
  val <- generate tc schema
  case termToInt val of
    Just idx -> let v = options !! (fromIntegral idx `mod` nOpts)
                in writer $ "{\"value\": " ++ show v ++ "}"
    Nothing  -> writer "{\"value\": 0}"
