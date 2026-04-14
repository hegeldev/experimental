{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Conformance test support for hegel-agda.
-- Each conformance binary uses this module to handle the common pattern:
-- read JSON params from argv, read env vars, run tests, write metrics.
module Conformance
  ( getTestCases
  , writeMetrics
  , Params(..)
  , readParams
  , runConformance
  , paramInt
  , paramDouble
  , paramBool
  , paramIntList
  , paramString
  , paramStringList
  , lookupParam
  , JVal(..)
  -- Agda FFI support
  , MetricsWriter(..)
  , writeMetricStr
  , runConformanceAgda
  ) where

import HegelFFI
import qualified Codec.CBOR.Term as CBOR
import Data.IORef
import System.Environment (getArgs, lookupEnv)
import System.IO (hPutStrLn, stderr, IOMode(..), openFile, hClose, Handle, hFlush)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Control.Exception (bracket)

-- Simple JSON value type (minimal, just what conformance needs)
data JVal
  = JNull
  | JBool Bool
  | JNum Double
  | JInt Integer     -- exact integer (avoids Double precision loss)
  | JStr String
  | JArr [JVal]
  | JObj [(String, JVal)]
  deriving (Show)

-- | Get number of test cases from env (default 50)
getTestCases :: IO Int
getTestCases = do
  val <- lookupEnv "CONFORMANCE_TEST_CASES"
  pure $ case val of
    Just s  -> case reads s of ((n,""):_) -> n; _ -> 50
    Nothing -> 50

-- | Get metrics file path from env
getMetricsFile :: IO (Maybe FilePath)
getMetricsFile = lookupEnv "CONFORMANCE_METRICS_FILE"

-- | Write a JSON line to the metrics file
writeMetrics :: IORef (Maybe Handle) -> String -> IO ()
writeMetrics ref json = do
  mh <- readIORef ref
  case mh of
    Just h  -> hPutStrLn h json >> hFlush h
    Nothing -> pure ()

-- | Trivial JSON parser for conformance params (no dependency on aeson)
data Params = Params [(String, JVal)]

readParams :: IO Params
readParams = do
  args <- getArgs
  case args of
    (json:_) -> pure (parseObj json)
    []       -> pure (Params [])

parseObj :: String -> Params
parseObj s = case dropSpaces s of
  ('{':rest) -> Params (parseFields rest)
  _          -> Params []
  where
    dropSpaces = dropWhile isSpace
    isSpace c = c == ' ' || c == '\n' || c == '\r' || c == '\t'

    parseFields :: String -> [(String, JVal)]
    parseFields s0 =
      let s = dropSpaces s0 in
      case s of
        ('}':_)  -> []
        ('"':_)  -> let (k, r1) = parseString s
                        r2 = case dropSpaces r1 of (':':r) -> r; r -> r
                        (v, r3) = parseValue (dropSpaces r2)
                        rest = case dropSpaces r3 of (',':r) -> r; r -> r
                    in (k, v) : parseFields rest
        _        -> []

    parseValue :: String -> (JVal, String)
    parseValue s0 =
      let s = dropSpaces s0 in
      case s of
        ('"':_)     -> let (str, r) = parseString s in (JStr str, r)
        ('t':'r':'u':'e':r) -> (JBool True, r)
        ('f':'a':'l':'s':'e':r) -> (JBool False, r)
        ('n':'u':'l':'l':r) -> (JNull, r)
        ('[':rest)   -> let (vs, r) = parseArray rest in (JArr vs, r)
        ('{':_)      -> let Params fs = parseObj (dropSpaces s0) in (JObj fs, skipObj (dropSpaces s0))
        _            -> let (numStr, r) = span (\c -> c `elem` ("0123456789.-eE+" :: String)) s
                        in if any (`elem` (".eE" :: String)) numStr
                           then (JNum (read numStr), r)
                           else (JInt (read numStr), r)

    parseString :: String -> (String, String)
    parseString ('"':rest) = go rest
      where
        go ('"':r)       = ("", r)
        go ('\\':'"':r)  = let (s, r') = go r in ('"':s, r')
        go ('\\':'\\':r) = let (s, r') = go r in ('\\':s, r')
        go ('\\':'/':r)  = let (s, r') = go r in ('/':s, r')
        go ('\\':'n':r)  = let (s, r') = go r in ('\n':s, r')
        go ('\\':'r':r)  = let (s, r') = go r in ('\r':s, r')
        go ('\\':'t':r)  = let (s, r') = go r in ('\t':s, r')
        go ('\\':'b':r)  = let (s, r') = go r in ('\b':s, r')
        go ('\\':'f':r)  = let (s, r') = go r in ('\f':s, r')
        go ('\\':'u':a:b:c:d:r) =
          let cp = hexVal a * 0x1000 + hexVal b * 0x100 + hexVal c * 0x10 + hexVal d
          in if cp >= 0xD800 && cp <= 0xDBFF  -- high surrogate
             then case r of
               ('\\':'u':a2:b2:c2:d2:r2) ->
                 let lo = hexVal a2 * 0x1000 + hexVal b2 * 0x100 + hexVal c2 * 0x10 + hexVal d2
                     full = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                     (s, r') = go r2
                 in (toEnum full : s, r')
               _ -> let (s, r') = go r in (toEnum cp : s, r')
             else let (s, r') = go r in (toEnum cp : s, r')
        go (c:r) = let (s, r') = go r in (c:s, r')
        go []    = ("", [])

        hexVal :: Char -> Int
        hexVal c | c >= '0' && c <= '9' = fromEnum c - fromEnum '0'
                 | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
                 | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
                 | otherwise = 0
    parseString s = ("", s)

    parseArray :: String -> ([JVal], String)
    parseArray s0 = case dropSpaces s0 of
      (']':r)  -> ([], r)
      _        -> let (v, r1) = parseValue (dropSpaces s0)
                      rest = case dropSpaces r1 of (',':r) -> r; r -> r
                  in let (vs, r2) = parseArray rest in (v:vs, r2)

    skipObj :: String -> String
    skipObj ('{':r) = skipBraces 1 r
    skipObj s = s
    skipBraces :: Int -> String -> String
    skipBraces 0 s = s
    skipBraces n ('{':r) = skipBraces (n+1) r
    skipBraces n ('}':r) = skipBraces (n-1) r
    skipBraces n ('"':r) = let (_,r') = parseString ('"':r) in skipBraces n r'
    skipBraces n (_:r) = skipBraces n r
    skipBraces _ [] = []

-- Param lookup helpers
lookupParam :: String -> Params -> Maybe JVal
lookupParam k (Params kvs) = lookup k kvs

paramInt :: String -> Params -> Maybe Int
paramInt k ps = case lookupParam k ps of
  Just (JNum n) -> Just (round n)
  Just (JInt n) -> Just (fromIntegral n)
  _             -> Nothing

paramDouble :: String -> Params -> Maybe Double
paramDouble k ps = case lookupParam k ps of
  Just (JNum n)  -> Just n
  Just (JInt n)  -> Just (fromIntegral n)
  _              -> Nothing

paramBool :: String -> Params -> Maybe Bool
paramBool k ps = case lookupParam k ps of
  Just (JBool b) -> Just b
  Just JNull     -> Nothing  -- null means "use default"
  _              -> Nothing

paramIntList :: String -> Params -> Maybe [Int]
paramIntList k ps = case lookupParam k ps of
  Just (JArr vs) -> Just [toInt v | v <- vs]
  _              -> Nothing
  where
    toInt (JNum n) = round n
    toInt (JInt n) = fromIntegral n
    toInt _        = 0

paramString :: String -> Params -> Maybe String
paramString k ps = case lookupParam k ps of
  Just (JStr s) -> Just s
  _             -> Nothing

paramStringList :: String -> Params -> Maybe [String]
paramStringList k ps = case lookupParam k ps of
  Just (JArr vs) -> Just [s | JStr s <- vs]
  _              -> Nothing

-- | Run a conformance test. Takes a function that receives TestCase, params, and metrics writer.
runConformance :: (TestCase -> Params -> (String -> IO ()) -> IO ()) -> IO ()
runConformance testFn = do
  params <- readParams
  nCases <- getTestCases
  mFilePath <- getMetricsFile
  metricsHandle <- newIORef Nothing
  case mFilePath of
    Just fp -> do
      h <- openFile fp AppendMode
      writeIORef metricsHandle (Just h)
    Nothing -> pure ()
  let settings = defaultSettings { sTestCases = nCases }
      writer = writeMetrics metricsHandle
  withHegelConnection settings $ \conn cs -> do
    result <- runTest conn cs settings "conformance" $ \tc ->
      testFn tc params writer
    case trError result of
      Just err -> hPutStrLn stderr ("Conformance error: " ++ err)
      Nothing  -> pure ()
  mh <- readIORef metricsHandle
  case mh of
    Just h  -> hClose h
    Nothing -> pure ()

-- ============================================================================
-- Agda FFI support
-- ============================================================================

-- | Opaque wrapper for the metrics writer function, used by Agda FFI.
newtype MetricsWriter = MetricsWriter (String -> IO ())

-- | Write a metric string via the wrapped writer.
writeMetricStr :: MetricsWriter -> String -> IO ()
writeMetricStr (MetricsWriter f) s = f s

-- | Run a conformance test with an Agda-friendly callback signature.
runConformanceAgda :: (TestCase -> Params -> MetricsWriter -> IO ()) -> IO ()
runConformanceAgda testFn = runConformance $ \tc params writer ->
  testFn tc params (MetricsWriter writer)
