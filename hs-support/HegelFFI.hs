{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}

module HegelFFI
  ( TestCase(..), Connection, Stream, Packet(..)
  , Settings(..), TestResult(..), Status(..)
  , withHegelConnection, spawnServer, performHandshake
  , runTest
  , generate, startSpan, stopSpan
  , newCollection, collectionMore, collectionReject, markComplete
  , hegelAssume, hegelNote, hegelTarget
  , HegelReject(..)
  , cborMap, cborText, cborInt, cborFloat, cborBool, cborNull, cborList, cborBytes
  , termToInt, termToDouble, termToBool, termToText, termToBytes, termToList
  , defaultSettings
  , runHegelTest, runHegelTests
  , StopTest(..)
  ) where

import qualified Codec.CBOR.Term as CBOR
import qualified Codec.CBOR.Read as CBOR.Read
import qualified Codec.CBOR.Write as CBOR.Write
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Builder as Builder
import Data.ByteString (ByteString)
import Data.Bits ((.&.), (.|.), shiftL, testBit, clearBit)
import Data.Digest.CRC32 (crc32)
import Data.IORef
import Data.Word (Word8, Word32)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Text as T
import Data.Text (Text)
import Control.Concurrent (forkIO, ThreadId, killThread)
import Control.Concurrent.MVar
import Control.Concurrent.Chan
import Control.Exception
import Control.Monad (when, unless, void, forever)
import System.IO (Handle, hSetBinaryMode, hFlush, hSetBuffering, BufferMode(..))
import System.Process
import System.Environment (lookupEnv)

-- Constants
packetMagic :: Word32
packetMagic = 0x4845474C

packetTerminator :: Word8
packetTerminator = 0x0A

replyBit :: Word32
replyBit = 1 `shiftL` 31

closeStreamMessageId :: Word32
closeStreamMessageId = replyBit - 1

closeStreamPayload :: ByteString
closeStreamPayload = BS.singleton 0xFE

-- Exceptions
data HegelReject = HegelReject deriving (Show)
instance Exception HegelReject

data HegelError = HegelError String deriving (Show)
instance Exception HegelError

data ServerExited = ServerExited deriving (Show)
instance Exception ServerExited

data StopTest = StopTest deriving (Show)
instance Exception StopTest

-- Packet
data Packet = Packet
  { pktStreamId  :: !Word32
  , pktMessageId :: !Word32
  , pktIsReply   :: !Bool
  , pktPayload   :: !ByteString
  } deriving (Show)

-- Wire format
writePacket :: Handle -> Packet -> IO ()
writePacket h pkt = do
  let payload = pktPayload pkt
      payloadLen = fromIntegral (BS.length payload) :: Word32
      msgIdRaw = if pktIsReply pkt
                 then pktMessageId pkt .|. replyBit
                 else pktMessageId pkt
      headerNoChecksum = LBS.toStrict $ Builder.toLazyByteString $ mconcat
        [ Builder.word32BE packetMagic
        , Builder.word32BE 0
        , Builder.word32BE (pktStreamId pkt)
        , Builder.word32BE msgIdRaw
        , Builder.word32BE payloadLen
        ]
      -- CRC covers the FULL 20-byte header (with checksum zeroed) + payload
      crcInput = headerNoChecksum <> payload
      checksum = crc32 crcInput
      finalHeader = LBS.toStrict $ Builder.toLazyByteString $ mconcat
        [ Builder.word32BE packetMagic
        , Builder.word32BE checksum
        , Builder.word32BE (pktStreamId pkt)
        , Builder.word32BE msgIdRaw
        , Builder.word32BE payloadLen
        ]
  BS.hPut h (finalHeader <> payload <> BS.singleton packetTerminator)
  hFlush h

readExact :: Handle -> Int -> IO ByteString
readExact h n = go n []
  where
    go 0 acc = pure (BS.concat (reverse acc))
    go remaining acc = do
      chunk <- BS.hGet h remaining
      when (BS.null chunk) $ throwIO ServerExited
      go (remaining - BS.length chunk) (chunk : acc)

readPacket :: Handle -> IO Packet
readPacket h = do
  hdr <- readExact h 20
  let magic      = getW32 hdr 0
      checksum   = getW32 hdr 4
      streamId   = getW32 hdr 8
      msgIdRaw   = getW32 hdr 12
      payloadLen = getW32 hdr 16
  unless (magic == packetMagic) $
    throwIO (HegelError $ "Bad magic: " ++ show magic)
  payload <- readExact h (fromIntegral payloadLen)
  term <- readExact h 1
  unless (term == BS.singleton packetTerminator) $
    throwIO (HegelError "Missing packet terminator")
  -- CRC covers full 20-byte header (with checksum zeroed) + payload
  let crcInput = (BS.take 4 hdr <> BS.pack [0,0,0,0] <> BS.drop 8 hdr) <> payload
      computed = crc32 crcInput
  unless (checksum == computed) $
    throwIO (HegelError $ "CRC mismatch: " ++ show checksum ++ " vs " ++ show computed)
  pure Packet { pktStreamId = streamId
              , pktMessageId = clearBit msgIdRaw 31
              , pktIsReply = testBit msgIdRaw 31
              , pktPayload = payload }

getW32 :: ByteString -> Int -> Word32
getW32 bs o = let b i = fromIntegral (BS.index bs (o+i)) :: Word32
              in (b 0 `shiftL` 24) .|. (b 1 `shiftL` 16) .|. (b 2 `shiftL` 8) .|. b 3

-- CBOR encode/decode
encodeCbor :: CBOR.Term -> ByteString
encodeCbor = LBS.toStrict . CBOR.Write.toLazyByteString . CBOR.encodeTerm

decodeCbor :: ByteString -> Either String CBOR.Term
decodeCbor bs = case CBOR.Read.deserialiseFromBytes CBOR.decodeTerm (LBS.fromStrict bs) of
  Left err     -> Left (show err)
  Right (_, t) -> Right t

-- CBOR constructors (String-based API for Agda FFI)
cborMap :: [(CBOR.Term, CBOR.Term)] -> CBOR.Term
cborMap = CBOR.TMap

cborText :: String -> CBOR.Term
cborText = CBOR.TString . T.pack

cborInt :: Integer -> CBOR.Term
cborInt = CBOR.TInteger

cborFloat :: Double -> CBOR.Term
cborFloat = CBOR.TDouble

cborBool :: Bool -> CBOR.Term
cborBool = CBOR.TBool

cborNull :: CBOR.Term
cborNull = CBOR.TNull

cborList :: [CBOR.Term] -> CBOR.Term
cborList = CBOR.TList

cborBytes :: ByteString -> CBOR.Term
cborBytes = CBOR.TBytes

-- CBOR deconstructors
termToInt :: CBOR.Term -> Maybe Integer
termToInt (CBOR.TInteger n) = Just n
termToInt (CBOR.TInt n)     = Just (fromIntegral n)
termToInt _                 = Nothing

termToDouble :: CBOR.Term -> Maybe Double
termToDouble (CBOR.TDouble d)  = Just d
termToDouble (CBOR.THalf d)    = Just (realToFrac d)
termToDouble (CBOR.TFloat d)   = Just (realToFrac d)
termToDouble (CBOR.TInteger n) = Just (fromIntegral n)
termToDouble (CBOR.TInt n)     = Just (fromIntegral n)
termToDouble _                 = Nothing

termToBool :: CBOR.Term -> Maybe Bool
termToBool (CBOR.TBool b) = Just b
termToBool _               = Nothing

termToText :: CBOR.Term -> Maybe String
termToText (CBOR.TString t) = Just (T.unpack t)
termToText (CBOR.TTagged 91 (CBOR.TBytes bs)) = Just (decodeWtf8 bs)
termToText _ = Nothing

decodeWtf8 :: ByteString -> String
decodeWtf8 = go . map fromIntegral . BS.unpack
  where
    go :: [Int] -> String
    go [] = []
    go (b:rest)
      | b < 0x80  = toEnum b : go rest
      | b < 0xE0  = case rest of
          (b1:r) -> toEnum (((b .&. 0x1F) `shiftL` 6) .|. (b1 .&. 0x3F)) : go r
          _ -> []
      | b < 0xF0  = case rest of
          (b1:b2:r) -> toEnum (((b .&. 0x0F) `shiftL` 12) .|. ((b1 .&. 0x3F) `shiftL` 6) .|. (b2 .&. 0x3F)) : go r
          _ -> []
      | otherwise = case rest of
          (b1:b2:b3:r) -> toEnum (((b .&. 0x07) `shiftL` 18) .|. ((b1 .&. 0x3F) `shiftL` 12) .|. ((b2 .&. 0x3F) `shiftL` 6) .|. (b3 .&. 0x3F)) : go r
          _ -> []

termToBytes :: CBOR.Term -> Maybe ByteString
termToBytes (CBOR.TBytes bs) = Just bs
termToBytes _                = Nothing

termToList :: CBOR.Term -> Maybe [CBOR.Term]
termToList (CBOR.TList ts)  = Just ts
termToList (CBOR.TListI ts) = Just ts
termToList _                = Nothing

termLookup :: Text -> CBOR.Term -> Maybe CBOR.Term
termLookup key (CBOR.TMap kvs) = lookup (CBOR.TString key) kvs
termLookup _ _ = Nothing

-- Stream type
data Stream = Stream
  { strmId        :: !Word32
  , strmConn      :: !Connection
  , strmNextMsgId :: !(IORef Word32)
  , strmReplies   :: !(IORef (Map Word32 ByteString))
  , strmRequests  :: !(IORef [Packet])
  , strmInbox     :: !(Chan Packet)
  , strmClosed    :: !(IORef Bool)
  }

newStream :: Connection -> Word32 -> IO Stream
newStream conn sid = do
  inbox <- getOrCreateInbox conn sid
  nextId <- newIORef 1
  replies <- newIORef Map.empty
  requests <- newIORef []
  closed <- newIORef False
  pure Stream { strmId = sid, strmConn = conn, strmNextMsgId = nextId
              , strmReplies = replies, strmRequests = requests
              , strmInbox = inbox, strmClosed = closed }

getOrCreateInbox :: Connection -> Word32 -> IO (Chan Packet)
getOrCreateInbox conn sid =
  modifyMVar (connInboxes conn) $ \m ->
    case Map.lookup sid m of
      Just inbox -> pure (m, inbox)
      Nothing -> do
        inbox <- newChan
        pure (Map.insert sid inbox m, inbox)

sendRequest :: Stream -> ByteString -> IO Word32
sendRequest strm payload = do
  msgId <- atomicModifyIORef' (strmNextMsgId strm) (\n -> (n + 1, n))
  connSendPacket (strmConn strm) Packet
    { pktStreamId = strmId strm, pktMessageId = msgId
    , pktIsReply = False, pktPayload = payload }
  pure msgId

receiveReply :: Stream -> Word32 -> IO ByteString
receiveReply strm targetId = go
  where
    go = do
      m <- readIORef (strmReplies strm)
      case Map.lookup targetId m of
        Just p -> do modifyIORef' (strmReplies strm) (Map.delete targetId); pure p
        Nothing -> do
          pkt <- readChan (strmInbox strm)
          if pktIsReply pkt
            then if pktMessageId pkt == targetId
                 then pure (pktPayload pkt)
                 else do modifyIORef' (strmReplies strm) (Map.insert (pktMessageId pkt) (pktPayload pkt)); go
            else do modifyIORef' (strmRequests strm) (++ [pkt]); go

receiveRequest :: Stream -> IO (Word32, ByteString)
receiveRequest strm = go
  where
    go = do
      reqs <- readIORef (strmRequests strm)
      case reqs of
        (pkt:rest) -> do writeIORef (strmRequests strm) rest; pure (pktMessageId pkt, pktPayload pkt)
        [] -> do
          pkt <- readChan (strmInbox strm)
          if pktIsReply pkt
            then do modifyIORef' (strmReplies strm) (Map.insert (pktMessageId pkt) (pktPayload pkt)); go
            else pure (pktMessageId pkt, pktPayload pkt)

writeReply :: Stream -> Word32 -> ByteString -> IO ()
writeReply strm msgId payload =
  connSendPacket (strmConn strm) Packet
    { pktStreamId = strmId strm, pktMessageId = msgId, pktIsReply = True, pktPayload = payload }

requestCbor :: Stream -> CBOR.Term -> IO CBOR.Term
requestCbor strm msg = do
  let payload = encodeCbor msg
  msgId <- sendRequest strm payload
  reply <- receiveReply strm msgId
  case decodeCbor reply of
    Left err -> throwIO (HegelError $ "CBOR decode: " ++ err)
    Right t  -> case termLookup "error" t of
        Just errTerm -> case termLookup "type" t of
          Just (CBOR.TString errType)
            | errType == "StopTest" -> throwIO StopTest
          _ -> throwIO (HegelError (showTerm errTerm))
        _ -> case termLookup "result" t of
          Just r  -> pure r
          Nothing -> pure t

showTerm :: CBOR.Term -> String
showTerm (CBOR.TString t) = T.unpack t
showTerm (CBOR.TInt n)    = show n
showTerm t                = show t

closeStream :: Stream -> IO ()
closeStream strm = do
  closed <- readIORef (strmClosed strm)
  unless closed $ do
    writeIORef (strmClosed strm) True
    connSendPacket (strmConn strm) Packet
      { pktStreamId = strmId strm, pktMessageId = closeStreamMessageId
      , pktIsReply = False, pktPayload = closeStreamPayload }

-- Connection type
data Connection = Connection
  { connWriter       :: !(MVar Handle)
  , connInboxes      :: !(MVar (Map Word32 (Chan Packet)))
  , connNextStreamId :: !(IORef Word32)
  , connServerExited :: !(IORef Bool)
  , connReaderThread :: !(IORef (Maybe ThreadId))
  }

connSendPacket :: Connection -> Packet -> IO ()
connSendPacket conn pkt = withMVar (connWriter conn) $ \h -> writePacket h pkt

newConnection :: Handle -> Handle -> IO Connection
newConnection reader writer = do
  hSetBinaryMode reader True
  hSetBinaryMode writer True
  hSetBuffering reader NoBuffering
  hSetBuffering writer NoBuffering
  wMVar <- newMVar writer
  inboxes <- newMVar Map.empty
  nextId <- newIORef 1
  exited <- newIORef False
  rTid <- newIORef Nothing
  let conn = Connection wMVar inboxes nextId exited rTid
  tid <- forkIO $ readerLoop conn reader
  writeIORef rTid (Just tid)
  pure conn

readerLoop :: Connection -> Handle -> IO ()
readerLoop conn reader = loop `catch` \(_ :: SomeException) ->
  writeIORef (connServerExited conn) True
  where
    loop = forever $ do
      pkt <- readPacket reader
      unless (pktMessageId pkt == closeStreamMessageId) $ do
        inbox <- getOrCreateInbox conn (pktStreamId pkt)
        writeChan inbox pkt

connNewStream :: Connection -> IO Stream
connNewStream conn = do
  n <- atomicModifyIORef' (connNextStreamId conn) (\i -> (i + 1, i))
  newStream conn ((n `shiftL` 1) .|. 1)

closeConnection :: Connection -> IO ()
closeConnection conn = do
  tid <- readIORef (connReaderThread conn)
  mapM_ killThread tid

-- Server management
spawnServer :: IO (Handle, Handle, ProcessHandle)
spawnServer = do
  cmdOverride <- lookupEnv "HEGEL_SERVER_COMMAND"
  let (cmd, args) = case cmdOverride of
        Just c  -> (head (words c), tail (words c) ++ ["--stdio"])
        Nothing -> ("python3", ["-m", "hegel", "--stdio"])
  (Just si, Just so, _, ph) <- createProcess (proc cmd args)
    { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe }
  hSetBinaryMode si True
  hSetBinaryMode so True
  hSetBuffering si NoBuffering
  hSetBuffering so NoBuffering
  pure (si, so, ph)

performHandshake :: Connection -> IO ()
performHandshake conn = do
  cs <- newStream conn 0
  msgId <- sendRequest cs "hegel_handshake_start"
  reply <- receiveReply cs msgId
  -- Version check: reply should be CBOR text "Hegel/0.10" or raw bytes
  case decodeCbor reply of
    Right (CBOR.TString v) ->
      unless (v == "Hegel/0.10") $
        throwIO (HegelError $ "Unsupported version: " ++ T.unpack v)
    _ -> pure ()  -- lenient on format

-- Test case context
data TestCase = TestCase
  { tcStream     :: !Stream
  , tcConnection :: !Connection
  , tcIsFinal    :: !(IORef Bool)
  }

-- Settings
data Settings = Settings
  { sTestCases   :: !Int
  , sSeed        :: !(Maybe Int)
  , sDerandomize :: !Bool
  , sDatabase    :: !(Maybe String)
  , sVerbosity   :: !String
  }

defaultSettings :: Settings
defaultSettings = Settings 100 Nothing False Nothing "normal"

-- Test result
data Status = Valid | Invalid | Interesting deriving (Show, Eq)

statusToText :: Status -> Text
statusToText Valid       = "VALID"
statusToText Invalid     = "INVALID"
statusToText Interesting = "INTERESTING"

data TestResult = TestResult
  { trPassed :: !Bool
  , trError  :: !(Maybe String)
  , trFlaky  :: !(Maybe String)
  } deriving (Show)

-- Core operations
generate :: TestCase -> CBOR.Term -> IO CBOR.Term
generate tc schema = requestCbor (tcStream tc) $ CBOR.TMap
  [ (CBOR.TString "command", CBOR.TString "generate")
  , (CBOR.TString "schema",  schema) ]

startSpan :: TestCase -> Int -> IO ()
startSpan tc label = void $ requestCbor (tcStream tc) $ CBOR.TMap
  [ (CBOR.TString "command", CBOR.TString "start_span")
  , (CBOR.TString "label",   CBOR.TInt label) ]

stopSpan :: TestCase -> Bool -> IO ()
stopSpan tc discard = void $ requestCbor (tcStream tc) $ CBOR.TMap
  [ (CBOR.TString "command", CBOR.TString "stop_span")
  , (CBOR.TString "discard", CBOR.TBool discard) ]

newCollection :: TestCase -> Int -> Maybe Int -> IO ()
newCollection tc minSz maxSz = void $ requestCbor (tcStream tc) $ CBOR.TMap $
  [ (CBOR.TString "command",  CBOR.TString "new_collection")
  , (CBOR.TString "min_size", CBOR.TInt minSz)
  ] ++ maybe [] (\ms -> [(CBOR.TString "max_size", CBOR.TInt ms)]) maxSz

collectionMore :: TestCase -> IO Bool
collectionMore tc = do
  r <- requestCbor (tcStream tc) $ CBOR.TMap
    [(CBOR.TString "command", CBOR.TString "collection_more")]
  case termToBool r of
    Just b  -> pure b
    Nothing -> case termLookup "more" r of
      Just (CBOR.TBool b) -> pure b
      _ -> throwIO (HegelError "Expected bool from collection_more")

collectionReject :: TestCase -> IO ()
collectionReject tc = void $ requestCbor (tcStream tc) $ CBOR.TMap
  [(CBOR.TString "command", CBOR.TString "collection_reject")]

markComplete :: TestCase -> Status -> Maybe String -> IO ()
markComplete tc status origin = do
  let fields = [ (CBOR.TString "command", CBOR.TString "mark_complete")
               , (CBOR.TString "status",  CBOR.TString (statusToText status))
               ] ++ case origin of
                      Just o  -> [(CBOR.TString "origin", CBOR.TString (T.pack o))]
                      Nothing -> [(CBOR.TString "origin", CBOR.TNull)]
  void $ requestCbor (tcStream tc) (CBOR.TMap fields)

hegelAssume :: TestCase -> Bool -> IO ()
hegelAssume _ True  = pure ()
hegelAssume _ False = throwIO HegelReject

hegelNote :: TestCase -> String -> IO ()
hegelNote tc msg = void $ requestCbor (tcStream tc) $ CBOR.TMap
  [ (CBOR.TString "command", CBOR.TString "note")
  , (CBOR.TString "message", CBOR.TString (T.pack msg)) ]

hegelTarget :: TestCase -> Double -> String -> IO ()
hegelTarget tc value label = void $ requestCbor (tcStream tc) $ CBOR.TMap
  [ (CBOR.TString "command", CBOR.TString "target")
  , (CBOR.TString "value",   CBOR.TDouble value)
  , (CBOR.TString "label",   CBOR.TString (T.pack label)) ]

-- Test runner
withHegelConnection :: Settings -> (Connection -> Stream -> IO a) -> IO a
withHegelConnection _settings action = do
  (serverIn, serverOut, ph) <- spawnServer
  conn <- newConnection serverOut serverIn
  performHandshake conn
  cs <- newStream conn 0
  action conn cs `finally` do
    closeConnection conn
    terminateProcess ph
    void (waitForProcess ph)

runTest :: Connection -> Stream -> Settings -> String
        -> (TestCase -> IO ()) -> IO TestResult
runTest conn cs settings _testName testFn = do
  ts <- connNewStream conn
  let msg = CBOR.TMap
        [ (CBOR.TString "command",      CBOR.TString "run_test")
        , (CBOR.TString "test_cases",   CBOR.TInt (sTestCases settings))
        , (CBOR.TString "seed",         maybe CBOR.TNull CBOR.TInt (sSeed settings))
        , (CBOR.TString "stream_id",    CBOR.TInt (fromIntegral (strmId ts)))
        , (CBOR.TString "database_key", CBOR.TNull)
        , (CBOR.TString "derandomize",  CBOR.TBool (sDerandomize settings))
        ]
  _ <- requestCbor cs msg
  processEvents conn ts testFn

processEvents :: Connection -> Stream -> (TestCase -> IO ()) -> IO TestResult
processEvents conn ts testFn = loop where
  loop = do
    (msgId, payload) <- receiveRequest ts
    case decodeCbor payload of
      Left err -> throwIO (HegelError $ "Bad CBOR: " ++ err)
      Right t -> do
        let ev = termLookup "event" t
        case ev of
          Just (CBOR.TString "test_case") -> do
              let dsId = case termLookup "stream_id" t >>= termToInt of
                    Just n  -> fromIntegral n :: Word32
                    Nothing -> error "missing stream_id in test_case"
              writeReply ts msgId (encodeCbor $ CBOR.TMap [(CBOR.TString "result", CBOR.TNull)])
              ds <- newStream conn dsId
              isFinal <- newIORef False
              let tc = TestCase ds conn isFinal
              result <- try (testFn tc) :: IO (Either SomeException ())
              case result of
                Right () -> do
                  markComplete tc Valid Nothing `catch` \StopTest -> pure ()
                  closeStream ds
                Left e
                  | Just StopTest <- fromException e -> closeStream ds
                  | Just HegelReject <- fromException e -> do
                      markComplete tc Invalid Nothing `catch` \StopTest -> pure ()
                      closeStream ds
                  | otherwise -> do
                      markComplete tc Interesting (Just (show e)) `catch` \StopTest -> pure ()
                      closeStream ds
              loop
          Just (CBOR.TString "test_done") -> do
              let results = termLookup "results" t
                  passed = case results >>= termLookup "passed" >>= termToBool of
                             Just b -> b; Nothing -> True
                  err = results >>= termLookup "error" >>= termToText
                  flaky = results >>= termLookup "flaky" >>= termToText
              writeReply ts msgId (encodeCbor $ CBOR.TMap [(CBOR.TString "result", CBOR.TBool True)])
              closeStream ts
              pure TestResult { trPassed = passed, trError = err, trFlaky = flaky }
          Just (CBOR.TString other) ->
              throwIO (HegelError $ "Unknown event: " ++ T.unpack other)
          _ -> throwIO (HegelError $ "Missing event field in: " ++ show t)

-- | Run a single Hegel test. Returns True if passed, False if failed.
runHegelTest :: Settings -> String -> (TestCase -> IO ()) -> IO Bool
runHegelTest settings name testFn =
  withHegelConnection settings $ \conn cs -> do
    result <- runTest conn cs settings name testFn
    case trError result of
      Just err -> do
        putStrLn $ "FAIL: " ++ name ++ ": " ++ err
        pure False
      Nothing | trPassed result -> pure True
              | otherwise -> do
                  putStrLn $ "FAIL: " ++ name
                  pure False

-- | Run multiple named Hegel tests. Returns True if all passed.
runHegelTests :: Settings -> [(String, TestCase -> IO ())] -> IO Bool
runHegelTests settings tests =
  withHegelConnection settings $ \conn cs -> do
    results <- mapM (\(name, fn) -> do
      result <- runTest conn cs settings name fn
      case trError result of
        Just err -> do
          putStrLn $ "FAIL: " ++ name ++ ": " ++ err
          pure False
        Nothing | trPassed result -> do
                    putStrLn $ "PASS: " ++ name
                    pure True
                | otherwise -> do
                    putStrLn $ "FAIL: " ++ name
                    pure False
      ) tests
    pure (and results)
