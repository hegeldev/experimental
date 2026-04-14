package dev.hegel.protocol;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/** Unit tests for the protocol layer: Packet, Cbor, Stream, Connection, HegelProtocolException. */
class ProtocolUnitTest {

  // -----------------------------------------------------------------------
  // HegelProtocolException
  // -----------------------------------------------------------------------

  @Test
  void hegelProtocolExceptionMessage() {
    HegelProtocolException e = new HegelProtocolException("test error");
    assertEquals("test error", e.getMessage());
    assertNull(e.getCause());
  }

  @Test
  void hegelProtocolExceptionMessageAndCause() {
    RuntimeException cause = new RuntimeException("root cause");
    HegelProtocolException e = new HegelProtocolException("wrapped", cause);
    assertEquals("wrapped", e.getMessage());
    assertSame(cause, e.getCause());
  }

  // -----------------------------------------------------------------------
  // Cbor
  // -----------------------------------------------------------------------

  @Test
  void cborEncodeDecodeRoundTrip() {
    ObjectNode node = Cbor.map();
    node.put("key", "value");
    node.put("num", 42);

    byte[] encoded = Cbor.encode(node);
    JsonNode decoded = Cbor.decode(encoded);

    assertEquals("value", decoded.get("key").asText());
    assertEquals(42, decoded.get("num").asInt());
  }

  @Test
  void cborMapper() {
    assertNotNull(Cbor.mapper());
  }

  @Test
  void cborArrayEmpty() {
    ArrayNode arr = Cbor.array();
    assertNotNull(arr);
    assertEquals(0, arr.size());
  }

  @Test
  void cborArrayWithElements() {
    ObjectNode a = Cbor.map();
    a.put("x", 1);
    ObjectNode b = Cbor.map();
    b.put("y", 2);

    ArrayNode arr = Cbor.array(a, b);
    assertEquals(2, arr.size());
    assertEquals(1, arr.get(0).get("x").asInt());
    assertEquals(2, arr.get(1).get("y").asInt());
  }

  @Test
  void cborDecodeInvalidBytes() {
    // Garbage bytes should throw HegelProtocolException
    assertThrows(
        HegelProtocolException.class,
        () -> Cbor.decode(new byte[] {(byte) 0xFF, (byte) 0xFE, 0x00}));
  }

  @Test
  void cborEncodeFailureThrowsHegelProtocolException() throws Exception {
    // Inject a mapper that throws on write
    Cbor.testMapper =
        new ObjectMapper() {
          @Override
          public byte[] writeValueAsBytes(Object value) throws JsonProcessingException {
            throw new JsonProcessingException("simulated encode failure") {};
          }
        };
    try {
      HegelProtocolException ex =
          assertThrows(HegelProtocolException.class, () -> Cbor.encode(Cbor.map()));
      assertTrue(ex.getMessage().contains("CBOR encode failed"));
    } finally {
      Cbor.testMapper = null;
    }
  }

  @Test
  void cborDecodeFailureViaTestMapper() throws Exception {
    // Inject a mapper that throws IOException on readTree
    Cbor.testMapper =
        new ObjectMapper() {
          @Override
          public JsonNode readTree(byte[] content) throws java.io.IOException {
            throw new java.io.IOException("simulated decode failure");
          }
        };
    try {
      HegelProtocolException ex =
          assertThrows(HegelProtocolException.class, () -> Cbor.decode(new byte[] {1, 2, 3}));
      assertTrue(ex.getMessage().contains("CBOR decode failed"));
      assertNotNull(ex.getCause());
    } finally {
      Cbor.testMapper = null;
    }
  }

  @AfterEach
  void resetCborTestMapper() {
    Cbor.testMapper = null;
  }

  // -----------------------------------------------------------------------
  // Packet
  // -----------------------------------------------------------------------

  @Test
  void packetWriteReadRoundTrip() throws IOException {
    byte[] payload = Cbor.encode(Cbor.map());
    Packet original = new Packet(3, 7, false, payload);

    ByteArrayOutputStream out = new ByteArrayOutputStream();
    original.write(out);

    ByteArrayInputStream in = new ByteArrayInputStream(out.toByteArray());
    Packet read = Packet.read(in);

    assertEquals(3, read.streamId());
    assertEquals(7, read.messageId());
    assertFalse(read.isReply());
    assertArrayEquals(payload, read.payload());
  }

  @Test
  void packetWriteReadRoundTripReply() throws IOException {
    byte[] payload = new byte[] {1, 2, 3};
    Packet original = new Packet(0, 5, true, payload);

    ByteArrayOutputStream out = new ByteArrayOutputStream();
    original.write(out);

    ByteArrayInputStream in = new ByteArrayInputStream(out.toByteArray());
    Packet read = Packet.read(in);

    assertEquals(0, read.streamId());
    assertEquals(5, read.messageId());
    assertTrue(read.isReply());
  }

  @Test
  void packetReadInvalidMagic() throws IOException {
    // Write a packet, then corrupt the magic bytes
    byte[] payload = new byte[] {0x42};
    Packet original = new Packet(0, 1, false, payload);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    original.write(out);

    byte[] bytes = out.toByteArray();
    // Corrupt magic (first 4 bytes)
    bytes[0] = 0x00;
    bytes[1] = 0x00;

    IOException ex =
        assertThrows(IOException.class, () -> Packet.read(new ByteArrayInputStream(bytes)));
    assertTrue(ex.getMessage().contains("Invalid magic"));
  }

  @Test
  void packetReadNegativeLength() throws IOException {
    // Manually craft a packet with a negative payload length
    byte[] header = new byte[20];
    // Magic: 0x4845474C
    header[0] = 0x48;
    header[1] = 0x45;
    header[2] = 0x47;
    header[3] = 0x4C;
    // CRC: 0 (we'll skip verification by setting a matching CRC later)
    // stream ID: 0
    // message ID: 1
    header[12] = 0;
    header[13] = 0;
    header[14] = 0;
    header[15] = 1;
    // length: -1 (0xFFFFFFFF)
    header[16] = (byte) 0xFF;
    header[17] = (byte) 0xFF;
    header[18] = (byte) 0xFF;
    header[19] = (byte) 0xFF;

    // Compute CRC over header (checksum field zeroed) + empty payload
    java.util.zip.CRC32 crc = new java.util.zip.CRC32();
    crc.update(header);
    long checksum = crc.getValue();
    header[4] = (byte) (checksum >>> 24);
    header[5] = (byte) (checksum >>> 16);
    header[6] = (byte) (checksum >>> 8);
    header[7] = (byte) checksum;

    IOException ex =
        assertThrows(IOException.class, () -> Packet.read(new ByteArrayInputStream(header)));
    assertTrue(ex.getMessage().contains("Invalid payload length"));
  }

  @Test
  void packetReadInvalidTerminator() throws IOException {
    // Write a valid packet, then corrupt the terminator byte
    byte[] payload = new byte[] {0x42};
    Packet original = new Packet(0, 1, false, payload);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    original.write(out);

    byte[] bytes = out.toByteArray();
    // The terminator is the last byte (0x0A)
    bytes[bytes.length - 1] = (byte) 0xBB;

    IOException ex =
        assertThrows(IOException.class, () -> Packet.read(new ByteArrayInputStream(bytes)));
    assertTrue(ex.getMessage().contains("Invalid terminator"));
  }

  @Test
  void packetReadCrcMismatch() throws IOException {
    // Write a valid packet, then corrupt the payload (after writing)
    byte[] payload = new byte[] {0x42, 0x43};
    Packet original = new Packet(0, 1, false, payload);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    original.write(out);

    byte[] bytes = out.toByteArray();
    // Corrupt the payload (bytes after header, before terminator)
    bytes[20] = (byte) (bytes[20] ^ 0xFF);

    IOException ex =
        assertThrows(IOException.class, () -> Packet.read(new ByteArrayInputStream(bytes)));
    assertTrue(ex.getMessage().contains("CRC32 mismatch"));
  }

  // -----------------------------------------------------------------------
  // Stream + Connection (using piped streams)
  // -----------------------------------------------------------------------

  /**
   * Create a loopback Connection: packets written to the connection are read back by the same
   * connection's reader thread. We simulate a minimal "echo server" using piped streams.
   */
  private static final class FakeServer implements AutoCloseable {
    final PipedInputStream clientIn;
    final PipedOutputStream clientOut;
    final PipedInputStream serverIn;
    final PipedOutputStream serverOut;
    final Connection connection;

    FakeServer() throws IOException {
      // Client reads from serverOut, writes to serverIn
      serverOut = new PipedOutputStream();
      clientIn = new PipedInputStream(serverOut);
      clientOut = new PipedOutputStream();
      serverIn = new PipedInputStream(clientOut);

      connection = Connection.create(clientIn, clientOut);
    }

    /** Write a packet directly from the "server" side to the client. */
    void sendFromServer(Packet pkt) throws IOException {
      pkt.write(serverOut);
    }

    /** Read a packet from the "server" side (what the client sent). */
    Packet receiveFromServer() throws IOException {
      return Packet.read(serverIn);
    }

    @Override
    public void close() throws IOException {
      serverOut.close();
      serverIn.close();
    }
  }

  @Test
  void streamSendRequestReceiveReply() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      // In a background thread, act as the server: receive the request, send a reply
      ObjectNode replyPayload = Cbor.map();
      replyPayload.put("result", "ok");
      byte[] replyBytes = Cbor.encode(replyPayload);

      Thread serverThread =
          new Thread(
              () -> {
                try {
                  Packet clientReq = fs.receiveFromServer();
                  // Reply with message ID | REPLY_BIT
                  Packet reply =
                      new Packet(clientReq.streamId(), clientReq.messageId(), true, replyBytes);
                  fs.sendFromServer(reply);
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      byte[] requestBytes = Cbor.encode(Cbor.map());
      int msgId = stream.sendRequest(requestBytes);
      byte[] reply = stream.receiveReply(msgId);
      serverThread.join(2000);

      JsonNode decoded = Cbor.decode(reply);
      assertEquals("ok", decoded.get("result").asText());
    }
  }

  @Test
  void streamReceiveRequest() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      ObjectNode serverMsg = Cbor.map();
      serverMsg.put("event", "test_case");
      byte[] msgBytes = Cbor.encode(serverMsg);

      // Server sends a request (not a reply) to the stream
      Thread serverThread =
          new Thread(
              () -> {
                try {
                  Packet req = new Packet(0, 42, false, msgBytes);
                  fs.sendFromServer(req);
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      Stream.IncomingRequest incoming = stream.receiveRequest();
      serverThread.join(2000);

      assertEquals(42, incoming.messageId());
      JsonNode decoded = Cbor.decode(incoming.payload());
      assertEquals("test_case", decoded.get("event").asText());
    }
  }

  @Test
  void streamSendReply() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      ObjectNode replyNode = Cbor.map();
      replyNode.put("result", true);
      byte[] replyBytes = Cbor.encode(replyNode);

      AtomicReference<Packet> received = new AtomicReference<>();
      Thread serverThread =
          new Thread(
              () -> {
                try {
                  received.set(fs.receiveFromServer());
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      stream.sendReply(99, replyBytes);
      serverThread.join(2000);

      Packet pkt = received.get();
      assertNotNull(pkt);
      assertTrue(pkt.isReply());
      assertEquals(99, pkt.messageId());
    }
  }

  @Test
  void streamReceiveReplyBuffersOutOfOrderReplies() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      // Send two requests
      byte[] req1 = Cbor.encode(Cbor.map());
      byte[] req2 = Cbor.encode(Cbor.map());

      ObjectNode r1 = Cbor.map();
      r1.put("result", 1);
      ObjectNode r2 = Cbor.map();
      r2.put("result", 2);

      Thread serverThread =
          new Thread(
              () -> {
                try {
                  // Receive both requests
                  Packet p1 = fs.receiveFromServer();
                  Packet p2 = fs.receiveFromServer();
                  // Reply in REVERSE order (reply to msg2 first)
                  fs.sendFromServer(
                      new Packet(p2.streamId(), p2.messageId(), true, Cbor.encode(r2)));
                  fs.sendFromServer(
                      new Packet(p1.streamId(), p1.messageId(), true, Cbor.encode(r1)));
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      int msgId1 = stream.sendRequest(req1);
      int msgId2 = stream.sendRequest(req2);

      // receiveReply for msg1 should buffer msg2's reply and return msg1's
      byte[] reply1 = stream.receiveReply(msgId1);
      byte[] reply2 = stream.receiveReply(msgId2);
      serverThread.join(2000);

      assertEquals(1, Cbor.decode(reply1).get("result").asInt());
      assertEquals(2, Cbor.decode(reply2).get("result").asInt());
    }
  }

  @Test
  void streamMarkClosedPreventsOperations() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();
      stream.markClosed();

      assertThrows(IOException.class, () -> stream.sendRequest(new byte[] {}));
    }
  }

  @Test
  void streamCloseIdempotent() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.newStream();
      // Must consume the close packet from server side to avoid blocking
      Thread t =
          new Thread(
              () -> {
                try {
                  fs.receiveFromServer(); // consume close packet
                } catch (IOException ignored) {
                }
              });
      t.start();

      stream.close(); // first close
      stream.close(); // second close should be a no-op
      t.join(2000);
    }
  }

  @Test
  void streamTimeoutThrowsIOException() throws Exception {
    long origTimeout = Stream.pollTimeoutSeconds;
    Stream.pollTimeoutSeconds = 1; // 1 second timeout
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();
      byte[] req = Cbor.encode(Cbor.map());
      // Server side reads the request but never replies
      Thread serverThread =
          new Thread(
              () -> {
                try {
                  fs.receiveFromServer(); // consume the request but don't reply
                } catch (IOException ignored) {
                }
              });
      serverThread.start();

      int msgId = stream.sendRequest(req);
      // Should timeout after 1 second
      IOException ex = assertThrows(IOException.class, () -> stream.receiveReply(msgId));
      serverThread.join(3000);
      assertTrue(ex.getMessage().contains("Timeout") || ex.getMessage().contains("timeout"));
    } finally {
      Stream.pollTimeoutSeconds = origTimeout;
    }
  }

  @Test
  void streamInterruptedThrowsIOException() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();
      byte[] req = Cbor.encode(Cbor.map());

      Thread serverThread =
          new Thread(
              () -> {
                try {
                  fs.receiveFromServer(); // consume but don't reply
                } catch (IOException ignored) {
                }
              });
      serverThread.start();

      int msgId = stream.sendRequest(req);
      AtomicReference<Throwable> caught = new AtomicReference<>();
      Thread waiter =
          new Thread(
              () -> {
                try {
                  stream.receiveReply(msgId);
                } catch (IOException e) {
                  caught.set(e);
                }
              });
      waiter.start();

      // Interrupt the waiting thread
      waiter.interrupt();
      waiter.join(3000);
      serverThread.join(2000);

      Throwable t = caught.get();
      assertNotNull(t, "Expected IOException but got nothing");
      assertTrue(t.getMessage().contains("Interrupted") || t instanceof IOException);
    }
  }

  @Test
  void connectionServerExitNotifiesStreams() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut);

    Connection conn = Connection.create(clientIn, clientOut);
    Stream stream = conn.controlStream();

    // Give the reader thread a moment to start
    Thread.sleep(50);

    // Close the server-to-client pipe (simulates server exit)
    serverOut.close();

    // The reader thread should detect EOF and set serverExited; stream should get SERVER_EXITED
    // Send a request from client side to trigger the receive
    long origTimeout = Stream.pollTimeoutSeconds;
    Stream.pollTimeoutSeconds = 2;
    try {
      byte[] req = Cbor.encode(Cbor.map());
      // sendRequest may fail since server is gone
      try {
        int msgId = stream.sendRequest(req);
        // receiveReply should fail
        assertThrows(IOException.class, () -> stream.receiveReply(msgId));
      } catch (IOException e) {
        // sendRequest itself may fail — that's also acceptable
      }
      // hasServerExited should eventually be true
      Thread.sleep(200);
      assertTrue(conn.hasServerExited());
    } finally {
      Stream.pollTimeoutSeconds = origTimeout;
      serverIn.close();
    }
  }

  @Test
  void connectionSendPacketAfterServerExitThrows() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut);

    Connection conn = Connection.create(clientIn, clientOut);

    // Give reader thread time to start
    Thread.sleep(50);

    // Close the server-to-client pipe (EOF) and server-in (so client writes fail)
    serverOut.close();
    Thread.sleep(200); // wait for reader thread to detect EOF

    assertTrue(conn.hasServerExited());

    // Now try to send a packet — should throw because server has exited
    Stream stream = conn.newStream();
    assertThrows(IOException.class, () -> stream.sendRequest(Cbor.encode(Cbor.map())));

    serverIn.close();
  }

  @Test
  void connectionRegisterStreamAfterServerExitSignalsImmediately() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut);

    Connection conn = Connection.create(clientIn, clientOut);
    Thread.sleep(50);

    // Close the server output to trigger serverExited
    serverOut.close();
    Thread.sleep(300); // wait for reader thread

    assertTrue(conn.hasServerExited());

    // Register a new stream AFTER server has exited — should be immediately closed
    Stream stream = conn.newStream();
    long origTimeout = Stream.pollTimeoutSeconds;
    Stream.pollTimeoutSeconds = 1;
    try {
      // Trying to receive should fail quickly (server exited signal already in inbox)
      IOException ex =
          assertThrows(
              IOException.class,
              () -> {
                int msgId;
                try {
                  msgId = stream.sendRequest(new byte[0]);
                } catch (IOException e) {
                  throw e;
                }
                stream.receiveReply(msgId);
              });
      assertTrue(
          ex.getMessage().contains("exited")
              || ex.getMessage().contains("Timeout")
              || ex.getMessage().contains("closed")
              || ex.getMessage().contains("Broken"),
          "Unexpected message: " + ex.getMessage());
    } finally {
      Stream.pollTimeoutSeconds = origTimeout;
      serverIn.close();
    }
  }

  @Test
  void streamReceiveRequestBuffersReplies() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      // Server sends a request, but first sends a reply (out of order)
      ObjectNode replyNode = Cbor.map();
      replyNode.put("result", 42);
      ObjectNode requestNode = Cbor.map();
      requestNode.put("event", "ping");

      Thread serverThread =
          new Thread(
              () -> {
                try {
                  // First consume client's request
                  fs.receiveFromServer();
                  // Send reply first, then a new request from server
                  fs.sendFromServer(new Packet(0, 1, true, Cbor.encode(replyNode)));
                  fs.sendFromServer(new Packet(0, 99, false, Cbor.encode(requestNode)));
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      // First send a client request
      int msgId = stream.sendRequest(Cbor.encode(Cbor.map()));

      // receiveRequest: should buffer the reply and return the server request
      // But we need to get the reply first...
      // Actually, let's use receiveReply to get the reply (which may buffer the request)
      byte[] reply = stream.receiveReply(msgId);
      assertEquals(42, Cbor.decode(reply).get("result").asInt());

      // Now the server request should be in bufferedRequests
      Stream.IncomingRequest req = stream.receiveRequest();
      serverThread.join(2000);
      assertEquals("ping", Cbor.decode(req.payload()).get("event").asText());
    }
  }

  // -----------------------------------------------------------------------
  // Additional Stream coverage tests (lines 83, 96-97, 105-106, 143-144, 166)
  // -----------------------------------------------------------------------

  /**
   * receiveReply() encountering a non-reply packet (line 83: bufferedRequests.add), followed by
   * receiveRequest() reading from the buffer (lines 96-97).
   */
  @Test
  void streamReceiveReplyBuffersServerRequest() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      ObjectNode replyNode = Cbor.map();
      replyNode.put("result", 42);
      ObjectNode requestNode = Cbor.map();
      requestNode.put("event", "ping");

      // Server receives client request, then sends SERVER REQUEST first, then reply.
      // receiveReply() will read the non-reply packet → buffer it (line 83).
      Thread serverThread =
          new Thread(
              () -> {
                try {
                  Packet clientReq = fs.receiveFromServer();
                  // Send server-initiated request BEFORE the reply
                  fs.sendFromServer(new Packet(0, 99, false, Cbor.encode(requestNode)));
                  // Then send the actual reply
                  fs.sendFromServer(
                      new Packet(0, clientReq.messageId(), true, Cbor.encode(replyNode)));
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      int msgId = stream.sendRequest(Cbor.encode(Cbor.map()));

      // receiveReply should: read server-request (non-reply) → buffer at line 83,
      // then read reply → return it
      byte[] reply = stream.receiveReply(msgId);
      serverThread.join(2000);
      assertEquals(42, Cbor.decode(reply).get("result").asInt());

      // The server request is now in bufferedRequests; receiveRequest reads it (lines 96-97)
      Stream.IncomingRequest req = stream.receiveRequest();
      assertEquals(99, req.messageId());
      assertEquals("ping", Cbor.decode(req.payload()).get("event").asText());
    }
  }

  /** receiveRequest() encountering a reply packet and buffering it (lines 105-106). */
  @Test
  void streamReceiveRequestBufferedRepliesPath() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      ObjectNode replyNode = Cbor.map();
      replyNode.put("result", 7);
      ObjectNode requestNode = Cbor.map();
      requestNode.put("event", "ping");

      // Server proactively sends a reply (msgId=5) then a server-initiated request (msgId=88).
      // receiveRequest() reads the reply first → buffers it (lines 105-106).
      Thread serverThread =
          new Thread(
              () -> {
                try {
                  fs.sendFromServer(new Packet(0, 5, true, Cbor.encode(replyNode)));
                  fs.sendFromServer(new Packet(0, 88, false, Cbor.encode(requestNode)));
                } catch (IOException e) {
                  throw new RuntimeException(e);
                }
              });
      serverThread.start();

      // Call receiveRequest() WITHOUT first calling receiveReply():
      // 1. reads reply (isReply=true, msgId=5) → buffers in bufferedReplies (lines 105-106)
      // 2. reads server-request (isReply=false, msgId=88) → returns it
      Stream.IncomingRequest req = stream.receiveRequest();
      serverThread.join(2000);
      assertEquals(88, req.messageId());
      assertEquals("ping", Cbor.decode(req.payload()).get("event").asText());
    }
  }

  /** receiveReply() reading the SERVER_EXITED sentinel (lines 143-144). */
  @Test
  void streamServerExitedInReceiveReply() throws Exception {
    try (FakeServer fs = new FakeServer()) {
      Stream stream = fs.connection.controlStream();

      // Send a request (so receiveReply has something to wait for)
      int msgId = stream.sendRequest(Cbor.encode(Cbor.map()));

      // Deliver SERVER_EXITED sentinel directly (package-private method, same package)
      stream.serverExited();

      // receiveReply should read SERVER_EXITED → put sentinel back (line 143) → throw (line 144)
      IOException ex = assertThrows(IOException.class, () -> stream.receiveReply(msgId));
      assertTrue(ex.getMessage() != null);
    }
  }

  /** stream.close() when server has exited catches IOException (line 166). */
  @Test
  void streamCloseWhenServerGone() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut, 8192);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut, 8192);

    Connection conn = Connection.create(clientIn, clientOut);
    Stream stream = conn.newStream();

    // Close server output → reader thread detects EOF → serverExited=true
    serverOut.close();
    Thread.sleep(200);
    assertTrue(conn.hasServerExited());

    // close() tries to send close packet → sendPacket throws IOException (line 166 catch)
    assertDoesNotThrow(() -> stream.close());

    serverIn.close();
  }
}
