{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR
import qualified Data.ByteString as BS
import Data.Maybe (catMaybes)

main :: IO ()
main = runConformance $ \tc params writer -> do
  let schema = cborMap $ catMaybes
        [ Just (cborText "type", cborText "binary")
        , Just (cborText "min_size", cborInt (maybe 0 fromIntegral (paramInt "min_size" params)))
        , fmap (\v -> (cborText "max_size", cborInt (fromIntegral v))) (paramInt "max_size" params)
        ]
  val <- generate tc schema
  case termToBytes val of
    Just bs -> writer $ "{\"length\": " ++ show (BS.length bs) ++ "}"
    Nothing -> writer "{\"length\": 0}"
