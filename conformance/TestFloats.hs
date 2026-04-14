{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR
import Data.Maybe (catMaybes)

main :: IO ()
main = runConformance $ \tc params writer -> do
  let schema = cborMap $ catMaybes
        [ Just (cborText "type", cborText "float")
        , fmap (\v -> (cborText "min_value", cborFloat v)) (paramDouble "min_value" params)
        , fmap (\v -> (cborText "max_value", cborFloat v)) (paramDouble "max_value" params)
        , fmap (\v -> (cborText "allow_nan", cborBool v)) (paramBool "allow_nan" params)
        , fmap (\v -> (cborText "allow_infinity", cborBool v)) (paramBool "allow_infinity" params)
        , fmap (\v -> (cborText "exclude_min", cborBool v)) (paramBool "exclude_min" params)
        , fmap (\v -> (cborText "exclude_max", cborBool v)) (paramBool "exclude_max" params)
        ]
  val <- generate tc schema
  case termToDouble val of
    Just d | isNaN d     -> writer "{\"is_nan\": true}"
           | isInfinite d -> writer "{\"is_infinite\": true}"
           | otherwise   -> writer $ "{\"value\": " ++ showDouble d ++ "}"
    Nothing -> writer "{\"value\": 0.0}"

-- Show double without scientific notation issues
showDouble :: Double -> String
showDouble d
  | d == 0 && isNegativeZero d = "-0.0"
  | isInfinite d = if d > 0 then "Infinity" else "-Infinity"
  | isNaN d = "NaN"
  | otherwise = show d
