{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR
import Data.Maybe (catMaybes, fromMaybe)

main :: IO ()
main = runConformance $ \tc params writer -> do
  let mode = paramString "mode" params
      minSz = maybe 0 fromIntegral (paramInt "min_size" params)
      maxSz = fmap fromIntegral (paramInt "max_size" params)
      keySchema = cborMap $ catMaybes
        [ Just (cborText "type", cborText "integer")
        , fmap (\v -> (cborText "min_value", cborInt (fromIntegral v))) (paramInt "min_key" params)
        , fmap (\v -> (cborText "max_value", cborInt (fromIntegral v))) (paramInt "max_key" params)
        ]
      valSchema = cborMap $ catMaybes
        [ Just (cborText "type", cborText "integer")
        , fmap (\v -> (cborText "min_value", cborInt (fromIntegral v))) (paramInt "min_value" params)
        , fmap (\v -> (cborText "max_value", cborInt (fromIntegral v))) (paramInt "max_value" params)
        ]
  kvs <- case mode of
    Just "non_basic" -> do
      -- Composite path: use collection protocol
      startSpan tc 5  -- MAP
      newCollection tc (fromIntegral minSz) (fmap fromIntegral maxSz)
      result <- collectDictLoop tc keySchema valSchema []
      stopSpan tc False
      pure result
    _ -> do
      -- Basic path: dict schema
      let schema = cborMap $ catMaybes
            [ Just (cborText "type", cborText "dict")
            , Just (cborText "keys", keySchema)
            , Just (cborText "values", valSchema)
            , Just (cborText "min_size", cborInt minSz)
            , fmap (\v -> (cborText "max_size", cborInt v)) maxSz
            ]
      val <- generate tc schema
      case termToList val of
        Just pairs -> pure [getKV p | p <- pairs]
        Nothing -> pure []
  let size = length kvs
      keys = map fst kvs
      vals = map snd kvs
      minK = if null keys then 0 else minimum keys
      maxK = if null keys then 0 else maximum keys
      minV = if null vals then 0 else minimum vals
      maxV = if null vals then 0 else maximum vals
  writer $ "{\"size\": " ++ show size
        ++ ", \"min_key\": " ++ show minK
        ++ ", \"max_key\": " ++ show maxK
        ++ ", \"min_value\": " ++ show minV
        ++ ", \"max_value\": " ++ show maxV
        ++ "}"
  where
    getKV p = case termToList p of
      Just (k:v:_) -> (fromMaybe 0 (termToInt k), fromMaybe 0 (termToInt v))
      _ -> (0, 0)

collectDictLoop :: TestCase -> CBOR.Term -> CBOR.Term -> [(Integer, Integer)] -> IO [(Integer, Integer)]
collectDictLoop tc keySchema valSchema acc = do
  more <- collectionMore tc
  if more
    then do
      startSpan tc 6  -- MAP_ENTRY
      kVal <- generate tc keySchema
      vVal <- generate tc valSchema
      stopSpan tc False
      let k = fromMaybe 0 (termToInt kVal)
          v = fromMaybe 0 (termToInt vVal)
      collectDictLoop tc keySchema valSchema (acc ++ [(k, v)])
    else pure acc
