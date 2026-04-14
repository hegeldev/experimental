{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR
import Data.Maybe (catMaybes)

main :: IO ()
main = runConformance $ \tc params writer -> do
  let mode = paramString "mode" params
      minSz = maybe 0 fromIntegral (paramInt "min_size" params)
      maxSz = fmap fromIntegral (paramInt "max_size" params)
      elemSchema = cborMap $ catMaybes
        [ Just (cborText "type", cborText "integer")
        , fmap (\v -> (cborText "min_value", cborInt (fromIntegral v))) (paramInt "min_value" params)
        , fmap (\v -> (cborText "max_value", cborInt (fromIntegral v))) (paramInt "max_value" params)
        ]
  elems <- case mode of
    Just "non_basic" -> do
      -- Composite path: use collection protocol
      startSpan tc 1  -- LIST
      newCollection tc (fromIntegral minSz) (fmap fromIntegral maxSz)
      result <- collectLoop tc elemSchema []
      stopSpan tc False
      pure result
    _ -> do
      -- Basic path: use list schema
      let unique = paramBool "unique" params
          schema = cborMap $ catMaybes
            [ Just (cborText "type", cborText "list")
            , Just (cborText "elements", elemSchema)
            , Just (cborText "min_size", cborInt minSz)
            , fmap (\v -> (cborText "max_size", cborInt v)) maxSz
            , fmap (\v -> (cborText "unique", cborBool v)) unique
            ]
      val <- generate tc schema
      case termToList val of
        Just vs -> pure [case termToInt e of Just n -> n; Nothing -> 0 | e <- vs]
        Nothing -> pure []
  let valsJson = "[" ++ intercalate "," (map show elems) ++ "]"
  writer $ "{\"elements\": " ++ valsJson ++ "}"
  where
    intercalate _ [] = ""
    intercalate _ [x] = x
    intercalate sep (x:xs) = x ++ sep ++ intercalate sep xs

collectLoop :: TestCase -> CBOR.Term -> [Integer] -> IO [Integer]
collectLoop tc elemSchema acc = do
  more <- collectionMore tc
  if more
    then do
      startSpan tc 2  -- LIST_ELEMENT
      val <- generate tc elemSchema
      stopSpan tc False
      let n = case termToInt val of Just i -> i; Nothing -> 0
      collectLoop tc elemSchema (acc ++ [n])
    else pure acc
