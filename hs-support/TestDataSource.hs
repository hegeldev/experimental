{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Unit tests for the DataSource abstraction and protocol components.
-- Tests error injection via FakeDataSource and packet serialization.
module Main where

import HegelFFI
import qualified Codec.CBOR.Term as CBOR
import Control.Exception (catch, try, SomeException, throwIO)
import Data.IORef
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word32)
import Data.Bits (shiftL)
import Data.Digest.CRC32 (crc32)
import System.IO (hPutStrLn, stderr, hFlush, IOMode(..), openFile, hClose
                  , hSetBinaryMode, hSetBuffering, BufferMode(..))
import System.IO.Error (isEOFError)
import System.Exit (exitFailure, exitSuccess)

-- ============================================================================
-- Test framework
-- ============================================================================

data TestResult' = Pass String | Fail String String

runTests :: [IO TestResult'] -> IO ()
runTests tests = do
  results <- sequence tests
  let failures = [(n, m) | Fail n m <- results]
      passes   = [n | Pass n <- results]
  mapM_ (\(n, m) -> hPutStrLn stderr $ "  FAIL: " ++ n ++ " - " ++ m) failures
  mapM_ (\n -> hPutStrLn stderr $ "  PASS: " ++ n) passes
  hFlush stderr
  if null failures
    then do hPutStrLn stderr $ "All " ++ show (length results) ++ " protocol tests passed."
            exitSuccess
    else do hPutStrLn stderr $ show (length failures) ++ " of " ++ show (length results) ++ " tests FAILED."
            exitFailure

test :: String -> IO () -> IO TestResult'
test name action =
  (action >> pure (Pass name))
  `catch` \(e :: SomeException) -> pure (Fail name (show e))

assert :: Bool -> String -> IO ()
assert True  _   = pure ()
assert False msg = throwIO (userError msg)

-- ============================================================================
-- FakeDataSource tests
-- ============================================================================

testFakeGenerate :: IO TestResult'
testFakeGenerate = test "fake-generate: returns queued values" $ do
  ds <- fakeDataSource defaultFakeConfig { fdsGenerates = [CBOR.TBool True, CBOR.TInt 42] }
  v1 <- dsGenerate ds (CBOR.TMap [])
  assert (v1 == CBOR.TBool True) "expected True"
  v2 <- dsGenerate ds (CBOR.TMap [])
  assert (v2 == CBOR.TInt 42) "expected 42"

testFakeGenerateExhausted :: IO TestResult'
testFakeGenerateExhausted = test "fake-generate: throws StopTest when exhausted" $ do
  ds <- fakeDataSource defaultFakeConfig { fdsGenerates = [] }
  result <- try (dsGenerate ds (CBOR.TMap [])) :: IO (Either SomeException CBOR.Term)
  case result of
    Left _  -> pure ()  -- expected StopTest
    Right _ -> throwIO (userError "expected StopTest exception")

testFakeGenerateThrows :: IO TestResult'
testFakeGenerateThrows = test "fake-generate: throws StopTest on config flag" $ do
  ds <- fakeDataSource defaultFakeConfig { fdsThrowOnGenerate = True }
  result <- try (dsGenerate ds (CBOR.TMap [])) :: IO (Either SomeException CBOR.Term)
  case result of
    Left _  -> pure ()
    Right _ -> throwIO (userError "expected StopTest")

testFakeStartSpanThrows :: IO TestResult'
testFakeStartSpanThrows = test "fake-startSpan: throws on config flag" $ do
  ds <- fakeDataSource defaultFakeConfig { fdsThrowOnStartSpan = True }
  result <- try (dsStartSpan ds 1) :: IO (Either SomeException ())
  case result of
    Left _  -> pure ()
    Right _ -> throwIO (userError "expected error from startSpan")

testFakeStartSpanOk :: IO TestResult'
testFakeStartSpanOk = test "fake-startSpan: succeeds normally" $ do
  ds <- fakeDataSource defaultFakeConfig
  dsStartSpan ds 1  -- should not throw

testFakeStopSpan :: IO TestResult'
testFakeStopSpan = test "fake-stopSpan: always succeeds" $ do
  ds <- fakeDataSource defaultFakeConfig
  dsStopSpan ds False
  dsStopSpan ds True

testFakeCollectionMore :: IO TestResult'
testFakeCollectionMore = test "fake-collectionMore: respects count" $ do
  ds <- fakeDataSource defaultFakeConfig { fdsCollectionCount = 3 }
  b1 <- dsCollectionMore ds
  assert b1 "expected True (1)"
  b2 <- dsCollectionMore ds
  assert b2 "expected True (2)"
  b3 <- dsCollectionMore ds
  assert b3 "expected True (3)"
  b4 <- dsCollectionMore ds
  assert (not b4) "expected False (exhausted)"

testFakeCollectionZero :: IO TestResult'
testFakeCollectionZero = test "fake-collectionMore: zero count returns False immediately" $ do
  ds <- fakeDataSource defaultFakeConfig { fdsCollectionCount = 0 }
  b <- dsCollectionMore ds
  assert (not b) "expected False"

testFakeMarkComplete :: IO TestResult'
testFakeMarkComplete = test "fake-markComplete: succeeds silently" $ do
  ds <- fakeDataSource defaultFakeConfig
  dsMarkComplete ds Valid Nothing
  dsMarkComplete ds Invalid Nothing
  dsMarkComplete ds Interesting (Just "test error")

testFakeNote :: IO TestResult'
testFakeNote = test "fake-note: succeeds silently" $ do
  ds <- fakeDataSource defaultFakeConfig
  dsNote ds "test note"

testFakeTarget :: IO TestResult'
testFakeTarget = test "fake-target: succeeds silently" $ do
  ds <- fakeDataSource defaultFakeConfig
  dsTarget ds 0.5 "coverage"

-- ============================================================================
-- Packet serialization tests
-- ============================================================================

testPacketRoundTrip :: IO TestResult'
testPacketRoundTrip = test "packet: round-trip serialization" $ do
  -- Create a temp file pair for pipe simulation
  (readPath, writePath) <- do
    let p = "/tmp/hegel-test-packet"
    pure (p, p)
  wh <- openFile writePath WriteMode
  hSetBinaryMode wh True
  hSetBuffering wh NoBuffering
  let pkt = Packet { pktStreamId = 1, pktMessageId = 1
                    , pktIsReply = False, pktPayload = "hello" }
  writePacket wh pkt
  hClose wh
  rh <- openFile readPath ReadMode
  hSetBinaryMode rh True
  hSetBuffering rh NoBuffering
  pkt' <- readPacket rh
  hClose rh
  assert (pktStreamId pkt' == 1) "stream id mismatch"
  assert (pktMessageId pkt' == 1) "message id mismatch"
  assert (pktIsReply pkt' == False) "isReply mismatch"
  assert (pktPayload pkt' == "hello") "payload mismatch"

testPacketReplyBit :: IO TestResult'
testPacketReplyBit = test "packet: reply bit round-trip" $ do
  let p = "/tmp/hegel-test-packet-reply"
  wh <- openFile p WriteMode
  hSetBinaryMode wh True
  hSetBuffering wh NoBuffering
  let pkt = Packet { pktStreamId = 5, pktMessageId = 42
                    , pktIsReply = True, pktPayload = "" }
  writePacket wh pkt
  hClose wh
  rh <- openFile p ReadMode
  hSetBinaryMode rh True
  hSetBuffering rh NoBuffering
  pkt' <- readPacket rh
  hClose rh
  assert (pktStreamId pkt' == 5) "stream id"
  assert (pktMessageId pkt' == 42) "message id"
  assert (pktIsReply pkt' == True) "reply bit"

testCborRoundTrip :: IO TestResult'
testCborRoundTrip = test "cbor: encode/decode round-trip" $ do
  let term = CBOR.TMap
        [ (CBOR.TString "command", CBOR.TString "generate")
        , (CBOR.TString "value", CBOR.TInt 42)
        ]
  let bs = encodeCbor term
  case decodeCbor bs of
    Left err -> throwIO (userError $ "decode failed: " ++ err)
    Right decoded -> do
      -- Check structure preserved
      case decoded of
        CBOR.TMap _ -> pure ()
        _ -> throwIO (userError "expected TMap")

testCborIntegers :: IO TestResult'
testCborIntegers = test "cbor: integer round-trip" $ do
  let vals = [0, 1, -1, 127, -128, 1000, -1000, 2^32, -(2^32)]
  mapM_ (\v -> do
    let term = CBOR.TInteger v
        bs = encodeCbor term
    case decodeCbor bs of
      Left err -> throwIO (userError $ "decode failed for " ++ show v ++ ": " ++ err)
      Right _ -> pure ()
    ) vals

-- ============================================================================
-- Integration test: FakeDataSource with TestCase operations
-- ============================================================================

testFakeWithTestCase :: IO TestResult'
testFakeWithTestCase = test "fake-datasource: works through TestCase operations" $ do
  ds <- fakeDataSource defaultFakeConfig
    { fdsGenerates = [CBOR.TBool True, CBOR.TInt 99]
    , fdsCollectionCount = 2
    }
  -- We can't easily create a full TestCase without a real connection,
  -- but we can verify the DataSource methods work correctly
  v1 <- dsGenerate ds (CBOR.TMap [(CBOR.TString "type", CBOR.TString "boolean")])
  assert (v1 == CBOR.TBool True) "first generate"
  dsStartSpan ds 1
  dsNewCollection ds 0 (Just 5)
  b1 <- dsCollectionMore ds
  assert b1 "first more"
  dsStartSpan ds 2
  v2 <- dsGenerate ds (CBOR.TMap [(CBOR.TString "type", CBOR.TString "integer")])
  assert (v2 == CBOR.TInt 99) "second generate"
  dsStopSpan ds False
  b2 <- dsCollectionMore ds
  assert b2 "second more"
  b3 <- dsCollectionMore ds
  assert (not b3) "third more (exhausted)"
  dsStopSpan ds False
  dsMarkComplete ds Valid Nothing

-- ============================================================================
-- Main
-- ============================================================================

main :: IO ()
main = do
  hPutStrLn stderr "=== Protocol & DataSource Unit Tests ==="
  hFlush stderr
  runTests
    [ testFakeGenerate
    , testFakeGenerateExhausted
    , testFakeGenerateThrows
    , testFakeStartSpanThrows
    , testFakeStartSpanOk
    , testFakeStopSpan
    , testFakeCollectionMore
    , testFakeCollectionZero
    , testFakeMarkComplete
    , testFakeNote
    , testFakeTarget
    , testPacketRoundTrip
    , testPacketReplyBit
    , testCborRoundTrip
    , testCborIntegers
    , testFakeWithTestCase
    ]
