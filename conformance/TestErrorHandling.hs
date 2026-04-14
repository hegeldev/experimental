{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import Conformance
import qualified Codec.CBOR.Term as CBOR
import System.Environment (lookupEnv)
import Control.Exception (catch, SomeException)

main :: IO ()
main = do
  testMode <- lookupEnv "HEGEL_PROTOCOL_TEST_MODE"
  -- Choose generator based on test mode:
  -- Collection modes need to exercise the collection protocol (new_collection, collection_more)
  -- Other modes just need any generator (boolean is simplest)
  let isCollectionMode = case testMode of
        Just m  -> "collection" `isInfixOf` m
        Nothing -> False

  runConformance $ \tc _params writer -> do
    if isCollectionMode
      then do
        -- Use collection protocol: start list span, new_collection, collection_more loop
        startSpan tc 1  -- LIST label
        newCollection tc 0 (Just 5)
        collectLoop tc
        stopSpan tc False
      else do
        -- Simple generate: just draw a boolean
        _ <- generate tc (cborMap [(cborText "type", cborText "boolean")])
        pure ()
    writer "{}"
  where
    isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)
    isPrefixOf [] _ = True
    isPrefixOf _ [] = False
    isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys
    tails [] = [[]]
    tails xs@(_:xs') = xs : tails xs'

collectLoop :: TestCase -> IO ()
collectLoop tc = do
  more <- collectionMore tc
  if more
    then do
      startSpan tc 2  -- LIST_ELEMENT
      _ <- generate tc (cborMap [(cborText "type", cborText "integer"),
                                 (cborText "min_value", cborInt 0),
                                 (cborText "max_value", cborInt 100)])
      stopSpan tc False
      collectLoop tc
    else pure ()
