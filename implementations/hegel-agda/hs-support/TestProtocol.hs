{-# LANGUAGE OverloadedStrings #-}
module Main where

import HegelFFI
import qualified Codec.CBOR.Term as CBOR
import System.IO (hPutStrLn, stderr, hFlush)
import System.Exit (exitFailure, exitSuccess)

main :: IO ()
main = do
  hPutStrLn stderr "Starting protocol test..."
  hFlush stderr
  withHegelConnection defaultSettings $ \conn cs -> do
    hPutStrLn stderr "Connected to hegel-core, running test..."
    hFlush stderr
    result <- runTest conn cs defaultSettings "test_bool" $ \tc -> do
      -- Generate a boolean using the cborMap/cborText helpers
      let schema = cborMap
            [ (cborText "type", cborText "boolean") ]
      val <- generate tc schema
      hPutStrLn stderr $ "  Generated value: " ++ show val
      hFlush stderr
      case termToBool val of
        Just _b -> return ()
        Nothing -> hPutStrLn stderr ("  Warning: non-bool value: " ++ show val)
    hPutStrLn stderr $ "Test result: " ++ show result
    hFlush stderr
    if trPassed result
      then do hPutStrLn stderr "PASS"; exitSuccess
      else do hPutStrLn stderr "FAIL"; exitFailure
