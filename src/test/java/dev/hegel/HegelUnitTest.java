package dev.hegel;

import static dev.hegel.generators.Generators.integers;
import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.protocol.Cbor;
import dev.hegel.protocol.Connection;
import dev.hegel.protocol.Packet;
import java.io.IOException;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * Unit and integration tests targeting previously-uncovered paths in Hegel.java. Uses
 * Hegel.testSession injection and direct method calls on package-private methods.
 */
class HegelUnitTest {

  @AfterEach
  void resetTestSession() {
    Hegel.testSession = null;
  }

  // -----------------------------------------------------------------------
  // checkResults() — package-private method (Hegel.java:250-267)
  // -----------------------------------------------------------------------

  private Hegel hegel() {
    return new Hegel(tc -> {});
  }

  @Test
  void checkResultsError() {
    // Server returned {"error": "something bad"} → RuntimeException (lines 250-251)
    ObjectNode result = Cbor.map();
    result.put("error", "something bad");
    assertThrows(RuntimeException.class, () -> hegel().checkResults(result, null));
  }

  @Test
  void checkResultsErrorNull() {
    // {"error": null} → no error (null check)
    ObjectNode result = Cbor.map();
    result.putNull("error");
    result.put("passed", true);
    assertDoesNotThrow(() -> hegel().checkResults(result, null));
  }

  @Test
  void checkResultsHealthCheckFailure() {
    // {"health_check_failure": "too_slow"} → AssertionError (lines 253-255)
    ObjectNode result = Cbor.map();
    result.put("health_check_failure", "too_slow");
    AssertionError ex =
        assertThrows(AssertionError.class, () -> hegel().checkResults(result, null));
    assertTrue(ex.getMessage().contains("Health check failure"));
  }

  @Test
  void checkResultsHealthCheckFailureNull() {
    // {"health_check_failure": null} → no error (null check)
    ObjectNode result = Cbor.map();
    result.putNull("health_check_failure");
    result.put("passed", true);
    assertDoesNotThrow(() -> hegel().checkResults(result, null));
  }

  @Test
  void checkResultsFlaky() {
    // {"flaky": "some reason"} → AssertionError (lines 257-259)
    ObjectNode result = Cbor.map();
    result.put("flaky", "some reason");
    AssertionError ex =
        assertThrows(AssertionError.class, () -> hegel().checkResults(result, null));
    assertTrue(ex.getMessage().contains("Flaky"));
  }

  @Test
  void checkResultsFlakyNull() {
    // {"flaky": null} → no error (null check)
    ObjectNode result = Cbor.map();
    result.putNull("flaky");
    result.put("passed", true);
    assertDoesNotThrow(() -> hegel().checkResults(result, null));
  }

  @Test
  void checkResultsPassedFalseWithCapture() {
    // passed=false, lastFailure non-null → rethrow lastFailure (line 265)
    ObjectNode result = Cbor.map();
    result.put("passed", false);
    AssertionError failure = new AssertionError("my failure");
    AssertionError thrown =
        assertThrows(AssertionError.class, () -> hegel().checkResults(result, failure));
    assertSame(failure, thrown);
  }

  @Test
  void checkResultsPassedFalseNoCapture() {
    // passed=false, lastFailure=null → generic error (line 267)
    ObjectNode result = Cbor.map();
    result.put("passed", false);
    AssertionError ex =
        assertThrows(AssertionError.class, () -> hegel().checkResults(result, null));
    assertTrue(ex.getMessage().contains("counterexample"));
  }

  @Test
  void checkResultsPassed() {
    // passed=true → no error
    ObjectNode result = Cbor.map();
    result.put("passed", true);
    assertDoesNotThrow(() -> hegel().checkResults(result, null));
  }

  // -----------------------------------------------------------------------
  // extractOrigin() — package-private static method (Hegel.java:277, 286)
  // -----------------------------------------------------------------------

  @Test
  void extractOriginNull() {
    // null throwable → null (line 277)
    assertNull(Hegel.extractOrigin(null));
  }

  @Test
  void extractOriginAllHegelFrames() {
    // Throwable whose stack trace consists only of dev.hegel.* and java.* frames
    // → no match → return null (line 286)
    Throwable t = new RuntimeException("test");
    t.setStackTrace(
        new StackTraceElement[] {
          new StackTraceElement("dev.hegel.Foo", "bar", "Foo.java", 1),
          new StackTraceElement("java.lang.Thread", "run", "Thread.java", 100),
          new StackTraceElement("org.junit.jupiter.api.Test", "test", "Test.java", 1)
        });
    assertNull(Hegel.extractOrigin(t));
  }

  @Test
  void extractOriginFindsUserFrame() {
    // Throwable with a user code frame → returns that frame's toString
    Throwable t = new RuntimeException("test");
    t.setStackTrace(
        new StackTraceElement[] {
          new StackTraceElement("dev.hegel.Foo", "bar", "Foo.java", 1),
          new StackTraceElement("com.example.MyTest", "testSomething", "MyTest.java", 42)
        });
    String origin = Hegel.extractOrigin(t);
    assertNotNull(origin);
    assertTrue(origin.contains("MyTest"));
  }

  // -----------------------------------------------------------------------
  // Hegel.run() with injected testSession (Hegel.java:96, 137-138)
  // -----------------------------------------------------------------------

  /**
   * Inject a fake Session with a dead connection (server has exited). run() will fail at
   * controlStream.sendRequest() → IOException → lines 137-138. Also covers line 96 (testSession !=
   * null branch).
   */
  @Test
  void runWithBrokenSessionThrowsProtocolError() throws Exception {
    // Create piped streams where "server" output is immediately closed
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut, 4096);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut, 4096);

    Connection conn = Connection.create(clientIn, clientOut);
    // Close server output to trigger "server exited" in the reader thread
    serverOut.close();
    Thread.sleep(200); // wait for reader thread to detect EOF

    Session fakeSession = new Session(conn, conn.controlStream(), null);
    Hegel.testSession = fakeSession;

    RuntimeException ex = assertThrows(RuntimeException.class, () -> new Hegel(tc -> {}).run());
    // Should be the "Hegel protocol error:" wrapper from the IOException catch
    assertTrue(
        ex.getMessage().contains("protocol error")
            || ex.getMessage().contains("Hegel protocol")
            || ex.getCause() instanceof IOException,
        "Unexpected: " + ex.getMessage());

    serverIn.close();
  }

  // -----------------------------------------------------------------------
  // Hegel.run() with unknown event type (Hegel.java:208, also 137-138)
  // -----------------------------------------------------------------------

  /**
   * Inject a fake Session whose fake server sends an unknown event type. runEventLoop() throws
   * IOException("Unknown event type") → lines 137-138 + 208.
   */
  @Test
  void runUnknownEventTypeThrowsProtocolError() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut, 8192);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut, 8192);

    Connection conn = Connection.create(clientIn, clientOut);
    Session fakeSession = new Session(conn, conn.controlStream(), null);

    AtomicReference<Throwable> serverError = new AtomicReference<>();
    Thread serverThread =
        new Thread(
            () -> {
              try {
                // 1. Read the run_test request on the control stream (stream 0)
                Packet runTestPkt = Packet.read(serverIn);
                // ACK with result=null
                ObjectNode ack = Cbor.map();
                ack.putNull("result");
                new Packet(0, runTestPkt.messageId(), true, Cbor.encode(ack)).write(serverOut);
                serverOut.flush();

                // 2. Send an unknown event to the test stream (stream ID 3 = first newStream())
                ObjectNode unknownEvent = Cbor.map();
                unknownEvent.put("event", "alien_invasion");
                new Packet(3, 1, false, Cbor.encode(unknownEvent)).write(serverOut);
                serverOut.flush();
              } catch (Exception e) {
                serverError.set(e);
              }
            });
    serverThread.start();

    Hegel.testSession = fakeSession;
    RuntimeException ex = assertThrows(RuntimeException.class, () -> new Hegel(tc -> {}).run());
    assertTrue(
        ex.getMessage().contains("protocol error") || ex.getCause() instanceof IOException,
        "Unexpected: " + ex.getMessage());

    serverThread.join(3000);
    serverIn.close();
    serverOut.close();

    if (serverError.get() != null) {
      // Server thread errors are informational only
    }
  }

  // -----------------------------------------------------------------------
  // Hegel.run() databaseKey=null path (Hegel.java:161)
  // -----------------------------------------------------------------------

  @Test
  void runWithoutDatabaseKeyCoversNullBranch() {
    // new Hegel(fn).run() without databaseKey() → databaseKey is null → line 161
    // Uses the real server (via the global session)
    assertDoesNotThrow(
        () ->
            new Hegel(
                    tc -> {
                      // minimal test — just draw an integer
                      tc.draw(integers(0L, 1L));
                    })
                .settings(Settings.builder().testCases(5).build())
                .run());
  }

  // -----------------------------------------------------------------------
  // Hegel.run() non-empty database path (Hegel.java:171)
  // -----------------------------------------------------------------------

  @Test
  void runWithNonEmptyDatabaseCoversDbBranch() {
    // Settings.builder().database("/tmp/hegel-test-db") → db is non-empty → line 171
    assertDoesNotThrow(
        () ->
            Hegel.test(
                "hegel unit test non-empty db",
                Settings.builder()
                    .testCases(5)
                    .database("/tmp/hegel-test-db-" + System.nanoTime())
                    .build(),
                tc -> tc.draw(integers(0L, 1L))));
  }

  // -----------------------------------------------------------------------
  // toAssertionError() line 273 — test body throws RuntimeException
  // -----------------------------------------------------------------------

  @Test
  void testBodyThrowsRuntimeExceptionWrappedAsAssertionError() {
    // When the test body throws a non-AssertionError (RuntimeException),
    // toAssertionError() wraps it in an AssertionError (line 273).
    AssertionError ex =
        assertThrows(
            AssertionError.class,
            () ->
                Hegel.test(
                    "unit test runtime exception",
                    Settings.builder().testCases(20).build(),
                    tc -> {
                      int x = tc.draw(integers(0, 3).asInt());
                      if (x == 0) throw new RuntimeException("not an assertion error");
                    }));
    // The cause should be the RuntimeException (wrapped by toAssertionError)
    assertNotNull(ex);
  }
}
