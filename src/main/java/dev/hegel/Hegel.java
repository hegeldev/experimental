package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.protocol.Cbor;
import dev.hegel.protocol.Connection;
import dev.hegel.protocol.Stream;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.function.Consumer;

/**
 * Entry point for Hegel property-based testing.
 *
 * <h2>Usage</h2>
 * <pre>{@code
 * import static dev.hegel.Generators.*;
 *
 * Hegel.test("sort is idempotent", tc -> {
 *     List<Integer> xs = tc.draw(lists(integers()));
 *     List<Integer> sorted = sort(xs);
 *     assertEquals(sorted, sort(sorted));
 * });
 * }</pre>
 *
 * <p>This spawns a hegel-core server on first use and reuses it for
 * all tests in the JVM process.
 */
public class Hegel {

    private final Consumer<TestCase> testFn;
    private Settings settings = Settings.defaults();
    private String databaseKey = null;

    public Hegel(Consumer<TestCase> testFn) {
        this.testFn = testFn;
    }

    // -----------------------------------------------------------------------
    // Builder methods
    // -----------------------------------------------------------------------

    /** Override settings. Returns {@code this} for chaining. */
    public Hegel settings(Settings settings) {
        this.settings = settings;
        return this;
    }

    /** Set the database key for persisting failing examples across runs. */
    public Hegel databaseKey(String key) {
        this.databaseKey = key;
        return this;
    }

    // -----------------------------------------------------------------------
    // Static factory
    // -----------------------------------------------------------------------

    /**
     * Run a property-based test with default settings.
     *
     * <pre>{@code
     * Hegel.test("my property", tc -> {
     *     int x = tc.draw(Generators.integers());
     *     assertTrue(x == x);
     * });
     * }</pre>
     */
    public static void test(String name, Consumer<TestCase> fn) {
        new Hegel(fn).databaseKey(name).run();
    }

    /**
     * Run a property-based test with custom settings.
     */
    public static void test(String name, Settings settings, Consumer<TestCase> fn) {
        new Hegel(fn).databaseKey(name).settings(settings).run();
    }

    // -----------------------------------------------------------------------
    // Execution
    // -----------------------------------------------------------------------

    /**
     * Execute the property-based test.
     *
     * <p>Connects to the hegel server (spawning it on first use), runs the
     * configured number of test cases, and throws {@link AssertionError}
     * if any test case finds a counterexample.
     */
    public void run() {
        Session session = Session.get();
        Connection connection = session.connection();
        Stream controlStream = session.controlStream();

        Stream testStream = connection.newStream();

        try {
            // Build and send run_test message on the control stream
            ObjectNode runTestMsg = buildRunTestMessage(testStream.streamId());
            byte[] encoded = Cbor.encode(runTestMsg);
            int reqId = controlStream.sendRequest(encoded);
            controlStream.receiveReply(reqId); // consume the run_test ACK

            // Event loop: handle test_case and test_done events
            JsonNode resultData = runEventLoop(connection, testStream);

            // Handle final replays for interesting test cases
            int nInteresting = resultData.path("interesting_test_cases").asInt(0);
            AssertionError lastFailure = null;

            for (int i = 0; i < nInteresting; i++) {
                Stream.IncomingRequest req = testStream.receiveRequest();
                JsonNode event = Cbor.decode(req.payload());
                int subStreamId = event.path("stream_id").asInt();
                Stream testCaseStream = connection.connectStream(subStreamId);

                // Send ACK
                testStream.sendReply(req.messageId(), ackNull());

                ServerDataSource ds = new ServerDataSource(connection, testCaseStream);
                TestCaseResult result = runTestCase(ds, true);
                if (result instanceof TestCaseResult.Interesting interesting) {
                    lastFailure = toAssertionError(interesting.error());
                }
            }

            try {
                testStream.close();
            } catch (IOException ignored) {}

            // Check final results
            checkResults(resultData, lastFailure);

        } catch (IOException e) {
            throw new RuntimeException("Hegel protocol error: " + e.getMessage(), e);
        }
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    private ObjectNode buildRunTestMessage(int streamId) {
        ObjectNode msg = Cbor.map();
        msg.put("command", "run_test");
        msg.put("test_cases", settings.testCases());
        if (settings.seed() != null) {
            msg.put("seed", settings.seed());
        } else {
            msg.putNull("seed");
        }
        msg.put("stream_id", streamId);

        if (databaseKey != null) {
            // database_key is a binary blob in the protocol
            msg.put("database_key", databaseKey.getBytes(StandardCharsets.UTF_8));
        } else {
            msg.putNull("database_key");
        }

        msg.put("derandomize", settings.derandomize());

        // Database setting
        String db = settings.database();
        if (db != null && db.isEmpty()) {
            msg.putNull("database");  // disabled
        } else if (db != null) {
            msg.put("database", db);
        }
        // If db == null, omit the field (use server default)

        if (!settings.suppressHealthCheck().isEmpty()) {
            var arr = Cbor.array();
            for (String check : settings.suppressHealthCheck()) {
                arr.add(check);
            }
            msg.set("suppress_health_check", arr);
        }

        return msg;
    }

    private JsonNode runEventLoop(Connection connection, Stream testStream) throws IOException {
        byte[] ackNull = ackNull();

        while (true) {
            Stream.IncomingRequest req = testStream.receiveRequest();
            JsonNode event = Cbor.decode(req.payload());
            String eventType = event.path("event").asText("");

            if ("test_case".equals(eventType)) {
                int subStreamId = event.path("stream_id").asInt();
                Stream testCaseStream = connection.connectStream(subStreamId);

                // ACK BEFORE running the test (matches TypeScript/Rust behavior)
                testStream.sendReply(req.messageId(), ackNull);

                ServerDataSource ds = new ServerDataSource(connection, testCaseStream);
                runTestCase(ds, false);

            } else if ("test_done".equals(eventType)) {
                testStream.sendReply(req.messageId(), ackTrue());
                return event.path("results");
            } else {
                throw new IOException("Unknown event type: " + eventType);
            }
        }
    }

    TestCaseResult runTestCase(ServerDataSource ds, boolean isFinal) {
        TestCase tc = new TestCase(ds, isFinal);
        TestCaseResult result;
        String origin = null;

        try {
            testFn.accept(tc);
            result = new TestCaseResult.Valid();
        } catch (AssumeException e) {
            result = new TestCaseResult.Invalid();
        } catch (StopTestException e) {
            result = new TestCaseResult.Invalid();
        } catch (Throwable e) {
            result = new TestCaseResult.Interesting(e);
            origin = extractOrigin(e);

            if (isFinal) {
                System.err.println();
                System.err.println(e.getMessage());
                e.printStackTrace(System.err);
            }
        }

        // Send mark_complete unless the test case was aborted (StopTest)
        if (!ds.testAborted()) {
            String status = switch (result) {
                case TestCaseResult.Valid v -> "VALID";
                case TestCaseResult.Invalid i -> "INVALID";
                case TestCaseResult.Interesting i -> "INTERESTING";
            };
            ds.markComplete(status, origin);
        }

        return result;
    }

    private void checkResults(JsonNode resultData, AssertionError lastFailure) {
        if (resultData.has("error") && !resultData.get("error").isNull()) {
            throw new RuntimeException("Server error: " + resultData.get("error"));
        }
        if (resultData.has("health_check_failure") && !resultData.get("health_check_failure").isNull()) {
            throw new AssertionError("Health check failure:\n" +
                    resultData.get("health_check_failure").asText());
        }
        if (resultData.has("flaky") && !resultData.get("flaky").isNull()) {
            throw new AssertionError("Flaky test detected: " +
                    resultData.get("flaky").asText());
        }

        boolean passed = resultData.path("passed").asBoolean(true);
        if (!passed) {
            if (lastFailure != null) {
                throw lastFailure;
            }
            throw new AssertionError("Hegel found a counterexample (no failure message captured)");
        }
    }

    private static AssertionError toAssertionError(Throwable e) {
        if (e instanceof AssertionError ae) return ae;
        return new AssertionError(e.getMessage(), e);
    }

    private static String extractOrigin(Throwable e) {
        if (e == null || e.getStackTrace() == null) return null;
        for (StackTraceElement ste : e.getStackTrace()) {
            String cls = ste.getClassName();
            if (!cls.startsWith("dev.hegel.") && !cls.startsWith("java.") &&
                !cls.startsWith("sun.") && !cls.startsWith("jdk.") &&
                !cls.startsWith("org.junit.") && !cls.startsWith("com.fasterxml.")) {
                return ste.toString();
            }
        }
        return null;
    }

    static byte[] ackNull() {
        ObjectNode ack = Cbor.map();
        ack.putNull("result");
        return Cbor.encode(ack);
    }

    static byte[] ackTrue() {
        ObjectNode ack = Cbor.map();
        ack.put("result", true);
        return Cbor.encode(ack);
    }

    // -----------------------------------------------------------------------
    // TestCaseResult sealed hierarchy
    // -----------------------------------------------------------------------

    sealed interface TestCaseResult
            permits TestCaseResult.Valid, TestCaseResult.Invalid, TestCaseResult.Interesting {
        record Valid() implements TestCaseResult {}
        record Invalid() implements TestCaseResult {}
        record Interesting(Throwable error) implements TestCaseResult {}
    }
}
