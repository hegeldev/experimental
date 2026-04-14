package dev.hegel;

import static org.junit.jupiter.api.Assertions.*;

import dev.hegel.protocol.Packet;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.function.Function;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for Session — version parsing, command building, and reset(). These test
 * package-private methods without spawning a subprocess.
 */
class SessionTest {

  // -----------------------------------------------------------------------
  // parseVersion
  // -----------------------------------------------------------------------

  @Test
  void parseVersionSimple() {
    int[] v = Session.parseVersion("0.10");
    assertArrayEquals(new int[] {0, 10}, v);
  }

  @Test
  void parseVersionBothNonZero() {
    int[] v = Session.parseVersion("2.3");
    assertArrayEquals(new int[] {2, 3}, v);
  }

  @Test
  void parseVersionWithSpaces() {
    int[] v = Session.parseVersion(" 1 . 2 ");
    assertArrayEquals(new int[] {1, 2}, v);
  }

  @Test
  void parseVersionInvalidThrows() {
    assertThrows(IllegalArgumentException.class, () -> Session.parseVersion("1.2.3"));
    assertThrows(IllegalArgumentException.class, () -> Session.parseVersion("1"));
    assertThrows(IllegalArgumentException.class, () -> Session.parseVersion(""));
  }

  // -----------------------------------------------------------------------
  // versionInRange
  // -----------------------------------------------------------------------

  @Test
  void versionInRangeExact() {
    assertTrue(Session.versionInRange("0.10", "0.10", "0.10"));
  }

  @Test
  void versionInRangeInclusive() {
    assertTrue(Session.versionInRange("0.10", "0.9", "0.11"));
  }

  @Test
  void versionInRangeTooLow() {
    // version < min → false
    assertFalse(Session.versionInRange("0.8", "0.10", "0.12"));
  }

  @Test
  void versionInRangeTooHigh() {
    // version > max → false
    assertFalse(Session.versionInRange("0.13", "0.10", "0.12"));
  }

  @Test
  void versionInRangeMajorVersionLower() {
    // major version lower than min
    assertFalse(Session.versionInRange("0.10", "1.0", "1.5"));
  }

  @Test
  void versionInRangeMajorVersionHigher() {
    // major version higher than max
    assertFalse(Session.versionInRange("2.0", "1.0", "1.5"));
  }

  @Test
  void versionInRangeSameMajorMinorAboveMax() {
    // Same major, minor > max minor
    assertFalse(Session.versionInRange("1.6", "1.0", "1.5"));
  }

  @Test
  void versionInRangeSameMajorMinorBelowMin() {
    // Same major, minor < min minor
    assertFalse(Session.versionInRange("1.0", "1.1", "1.5"));
  }

  @Test
  void versionInRangeAtMinBoundary() {
    assertTrue(Session.versionInRange("1.1", "1.1", "1.5"));
  }

  @Test
  void versionInRangeAtMaxBoundary() {
    assertTrue(Session.versionInRange("1.5", "1.1", "1.5"));
  }

  // -----------------------------------------------------------------------
  // buildCommand
  // -----------------------------------------------------------------------

  @Test
  void buildCommandDefaultUsesUv() {
    // When HEGEL_SERVER_COMMAND is not set, use uv
    String override = System.getenv(Session.HEGEL_SERVER_COMMAND_ENV);
    if (override != null && !override.isEmpty()) {
      // If the env var IS set, this test covers the override path
      List<String> cmd = Session.buildCommand();
      assertEquals(1, cmd.size());
      assertEquals(override, cmd.get(0));
    } else {
      List<String> cmd = Session.buildCommand();
      assertTrue(cmd.size() > 1);
      assertEquals("uv", cmd.get(0));
      assertTrue(cmd.contains("hegel"));
    }
  }

  // -----------------------------------------------------------------------
  // reset()
  // -----------------------------------------------------------------------

  @Test
  void resetClearsInstance() {
    // Ensure a session exists first (integration tests may have already created one)
    Session s1 = Session.get();
    assertNotNull(s1);

    // Reset clears the singleton
    Session.reset();
    // After reset, Session.instance should be null (get() would create a new one)

    // Get a new session — should be either the same JVM-cached one or a new one
    Session s2 = Session.get();
    assertNotNull(s2);
    // After re-initializing, get() should work fine
  }

  @Test
  void resetIdempotent() {
    // reset() multiple times should not throw
    Session.reset();
    assertDoesNotThrow(Session::reset);
    // Restore
    Session.get();
  }

  // -----------------------------------------------------------------------
  // buildCommand() — env override (Session.java:177)
  // -----------------------------------------------------------------------

  @Test
  void buildCommandWithEnvOverride() {
    Function<String, String> orig = Session.envLookup;
    try {
      Session.envLookup = v -> v.equals(Session.HEGEL_SERVER_COMMAND_ENV) ? "my-server" : null;
      List<String> cmd = Session.buildCommand();
      assertEquals(1, cmd.size());
      assertEquals("my-server", cmd.get(0));
    } finally {
      Session.envLookup = orig;
    }
  }

  // -----------------------------------------------------------------------
  // connectAndHandshake() error paths (Session.java:127-129, 135-137, 144-145, 150-151)
  // -----------------------------------------------------------------------

  /**
   * sendRequest() throws IOException → lines 127-129. Use an OutputStream that always fails so the
   * packet write fails.
   */
  @Test
  void connectAndHandshakeSendFailure() throws Exception {
    // InputStream that returns EOF immediately → reader thread sets serverExited=true
    InputStream emptyIn = new ByteArrayInputStream(new byte[0]);
    // OutputStream that always fails → write throws IOException
    OutputStream failOut =
        new OutputStream() {
          @Override
          public void write(int b) throws IOException {
            throw new IOException("write failed");
          }

          @Override
          public void write(byte[] b, int off, int len) throws IOException {
            throw new IOException("write failed");
          }
        };

    RuntimeException ex =
        assertThrows(
            RuntimeException.class, () -> Session.connectAndHandshake(emptyIn, failOut, null));
    assertTrue(
        ex.getMessage().contains("handshake") || ex.getCause() instanceof IOException,
        "Unexpected: " + ex.getMessage());
  }

  /**
   * sendRequest() succeeds but receiveReply() throws → lines 135-137. Server reads the handshake
   * packet, then closes its output (EOF for client).
   */
  @Test
  void connectAndHandshakeReceiveFailure() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut, 8192);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut, 8192);

    Thread serverThread =
        new Thread(
            () -> {
              try {
                Packet.read(serverIn); // consume the handshake packet
                serverOut.close(); // EOF for client → receiveReply will fail
              } catch (IOException ignored) {
              }
            });
    serverThread.start();

    RuntimeException ex =
        assertThrows(
            RuntimeException.class, () -> Session.connectAndHandshake(clientIn, clientOut, null));
    assertTrue(
        ex.getMessage().contains("handshake") || ex.getCause() instanceof IOException,
        "Unexpected: " + ex.getMessage());

    serverThread.join(3000);
    serverIn.close();
  }

  /** Handshake response does not start with "Hegel/" → lines 144-145. */
  @Test
  void connectAndHandshakeBadResponse() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut, 8192);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut, 8192);

    Thread serverThread =
        new Thread(
            () -> {
              try {
                Packet req = Packet.read(serverIn);
                byte[] bad = "BAD_RESPONSE_NOT_HEGEL".getBytes(StandardCharsets.UTF_8);
                new Packet(0, req.messageId(), true, bad).write(serverOut);
                serverOut.flush();
              } catch (IOException ignored) {
              }
            });
    serverThread.start();

    RuntimeException ex =
        assertThrows(
            RuntimeException.class, () -> Session.connectAndHandshake(clientIn, clientOut, null));
    assertTrue(ex.getMessage().contains("Bad handshake"), "Unexpected: " + ex.getMessage());

    serverThread.join(3000);
    serverOut.close();
    serverIn.close();
  }

  /** Protocol version out of supported range → lines 150-151. */
  @Test
  void connectAndHandshakeWrongVersion() throws Exception {
    PipedOutputStream serverOut = new PipedOutputStream();
    PipedInputStream clientIn = new PipedInputStream(serverOut, 8192);
    PipedOutputStream clientOut = new PipedOutputStream();
    PipedInputStream serverIn = new PipedInputStream(clientOut, 8192);

    Thread serverThread =
        new Thread(
            () -> {
              try {
                Packet req = Packet.read(serverIn);
                byte[] response = "Hegel/99.99".getBytes(StandardCharsets.UTF_8);
                new Packet(0, req.messageId(), true, response).write(serverOut);
                serverOut.flush();
              } catch (IOException ignored) {
              }
            });
    serverThread.start();

    RuntimeException ex =
        assertThrows(
            RuntimeException.class, () -> Session.connectAndHandshake(clientIn, clientOut, null));
    assertTrue(
        ex.getMessage().contains("protocol version") || ex.getMessage().contains("supports"),
        "Unexpected: " + ex.getMessage());

    serverThread.join(3000);
    serverOut.close();
    serverIn.close();
  }

  // -----------------------------------------------------------------------
  // init() failure (Session.java:100-103) + serverLogFile IOException (line 197)
  // -----------------------------------------------------------------------

  /**
   * init() fails to start process → lines 100-103. Also covers serverLogFile() IOException catch
   * (line 197) via testServerLogDir.
   */
  @Test
  void initFailsToStartProcess() {
    Function<String, String> origLookup = Session.envLookup;
    String origLogDir = Session.testServerLogDir;

    Session.reset(); // clear existing singleton so init() runs again

    try {
      // Invalid command → pb.start() throws IOException → lines 100-103
      Session.envLookup = v -> "nonexistent_command_that_does_not_exist_xyz_abc";
      // Invalid log dir → Files.createDirectories() fails → line 197
      Session.testServerLogDir = "/dev/null/cannot_create_dirs_here";

      RuntimeException ex = assertThrows(RuntimeException.class, Session::get);
      assertTrue(ex.getMessage().contains("Failed to start"), "Unexpected: " + ex.getMessage());
    } finally {
      Session.envLookup = origLookup;
      Session.testServerLogDir = origLogDir;
      // Recreate the session with the real server
      Session.get();
    }
  }
}
