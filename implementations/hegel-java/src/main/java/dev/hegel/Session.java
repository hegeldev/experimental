package dev.hegel;

import dev.hegel.protocol.Connection;
import dev.hegel.protocol.Stream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;

/**
 * Manages the hegel-core subprocess and the underlying {@link Connection}.
 *
 * <p>A single session is shared across all tests in the JVM process. It is created lazily on first
 * use via {@link #get()}.
 */
public class Session {

  static final String HEGEL_SERVER_VERSION = "0.4.0";
  static final String SUPPORTED_PROTOCOL_MIN = "0.10";
  static final String SUPPORTED_PROTOCOL_MAX = "0.10";
  static final String HEGEL_SERVER_COMMAND_ENV = "HEGEL_SERVER_COMMAND";
  static final String HEGEL_SERVER_DIR = ".hegel";
  static final String HANDSHAKE_STRING = "hegel_handshake_start";

  private static volatile Session instance;
  private static final Object lock = new Object();
  private static final AtomicInteger logCounter = new AtomicInteger(0);

  /** Package-private: injectable env lookup for testing buildCommand(). */
  static Function<String, String> envLookup = System::getenv;

  /** Package-private: injectable server log directory for testing serverLogFile(). */
  static String testServerLogDir = null;

  final Connection connection;
  final Stream controlStream;
  private final Process process;

  Session(Connection connection, Stream controlStream, Process process) {
    this.connection = connection;
    this.controlStream = controlStream;
    this.process = process;
  }

  /** Get (or lazily create) the global session. */
  public static Session get() {
    if (instance == null) {
      synchronized (lock) {
        if (instance == null) {
          instance = init();
        }
      }
    }
    return instance;
  }

  /** Reset the session (for testing purposes). */
  static void reset() {
    synchronized (lock) {
      if (instance != null) {
        instance.process.destroyForcibly();
        instance = null;
      }
    }
  }

  public Connection connection() {
    return connection;
  }

  public Stream controlStream() {
    return controlStream;
  }

  // -----------------------------------------------------------------------
  // Initialization
  // -----------------------------------------------------------------------

  private static Session init() {
    List<String> command = buildCommand();

    // Set up server log file
    File logFile = serverLogFile();

    ProcessBuilder pb = new ProcessBuilder(command);
    pb.redirectError(logFile);
    pb.environment().put("PYTHONUNBUFFERED", "1");

    Process process;
    try {
      process = pb.start();
    } catch (IOException e) {
      throw new RuntimeException(
          "Failed to start hegel-core server: "
              + e.getMessage()
              + "\n"
              + "Command: "
              + String.join(" ", command)
              + "\n"
              + "Is 'uv' installed? Run: curl -LsSf https://astral.sh/uv/install.sh | sh",
          e);
    }

    return connectAndHandshake(process.getInputStream(), process.getOutputStream(), process);
  }

  /**
   * Perform the connection handshake with a hegel-core server reachable via the given streams.
   * Package-private for testing with fake servers.
   */
  static Session connectAndHandshake(InputStream in, OutputStream out, Process process) {
    Connection connection = Connection.create(in, out);
    Stream controlStream = connection.controlStream();

    // Perform handshake (raw bytes, not CBOR)
    byte[] handshakeBytes = HANDSHAKE_STRING.getBytes(StandardCharsets.UTF_8);
    int handshakeMsgId;
    try {
      handshakeMsgId = controlStream.sendRequest(handshakeBytes);
    } catch (IOException e) {
      destroyProcessSafely(process);
      throw new RuntimeException("Failed to send handshake: " + e.getMessage(), e);
    }

    byte[] handshakeResponseBytes;
    try {
      handshakeResponseBytes = controlStream.receiveReply(handshakeMsgId);
    } catch (IOException e) {
      destroyProcessSafely(process);
      throw new RuntimeException(
          "Failed to receive handshake response. " + "Check server logs for server output.", e);
    }

    String responseStr = new String(handshakeResponseBytes, StandardCharsets.UTF_8);
    if (!responseStr.startsWith("Hegel/")) {
      destroyProcessSafely(process);
      throw new RuntimeException("Bad handshake response: " + responseStr);
    }

    String serverVersion = responseStr.substring("Hegel/".length());
    if (!versionInRange(serverVersion, SUPPORTED_PROTOCOL_MIN, SUPPORTED_PROTOCOL_MAX)) {
      destroyProcessSafely(process);
      throw new RuntimeException(
          "hegel-java supports protocol versions "
              + SUPPORTED_PROTOCOL_MIN
              + " through "
              + SUPPORTED_PROTOCOL_MAX
              + ", but the server is using protocol version "
              + serverVersion);
    }

    Session session = new Session(connection, controlStream, process);

    // Register shutdown hook to clean up the process
    if (process != null) {
      Runtime.getRuntime().addShutdownHook(new Thread(() -> destroyProcessSafely(process)));
    }

    return session;
  }

  /** Package-private: destroy a process, ignoring errors. Safe to call with null. */
  static void destroyProcessSafely(Process process) {
    if (process != null) {
      process.destroy();
    }
  }

  static List<String> buildCommand() {
    String override = envLookup.apply(HEGEL_SERVER_COMMAND_ENV);
    if (override != null && !override.isEmpty()) {
      return List.of(override);
    }

    List<String> cmd = new ArrayList<>();
    cmd.add("uv");
    cmd.add("tool");
    cmd.add("run");
    cmd.add("--from");
    cmd.add("hegel-core==" + HEGEL_SERVER_VERSION);
    cmd.add("hegel");
    cmd.add("--stdio");
    cmd.add("--verbosity");
    cmd.add("normal");
    return cmd;
  }

  private static File serverLogFile() {
    String dir = testServerLogDir != null ? testServerLogDir : HEGEL_SERVER_DIR;
    try {
      Files.createDirectories(Path.of(dir));
    } catch (IOException e) {
      // ignore — best-effort logging
    }
    long pid = ProcessHandle.current().pid();
    int idx = logCounter.getAndIncrement();
    return new File(dir, "server." + pid + "-" + idx + ".log");
  }

  // -----------------------------------------------------------------------
  // Version parsing
  // -----------------------------------------------------------------------

  static int[] parseVersion(String s) {
    String[] parts = s.split("\\.");
    if (parts.length != 2) {
      throw new IllegalArgumentException("Invalid version: " + s);
    }
    return new int[] {Integer.parseInt(parts[0].trim()), Integer.parseInt(parts[1].trim())};
  }

  static boolean versionInRange(String version, String min, String max) {
    int[] v = parseVersion(version);
    int[] lo = parseVersion(min);
    int[] hi = parseVersion(max);
    if (v[0] < lo[0] || (v[0] == lo[0] && v[1] < lo[1])) return false;
    if (v[0] > hi[0] || (v[0] == hi[0] && v[1] > hi[1])) return false;
    return true;
  }
}
