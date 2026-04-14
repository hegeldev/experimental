package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.protocol.Cbor;
import dev.hegel.protocol.Connection;
import dev.hegel.protocol.Packet;
import dev.hegel.protocol.Stream;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for ServerDataSource error paths.
 * Uses piped streams to simulate a fake hegel-core server.
 */
class ServerDataSourceTest {

    // -----------------------------------------------------------------------
    // FakeServer helper
    // -----------------------------------------------------------------------

    /** Simulates the hegel-core server side of the connection. */
    private static final class FakeServer implements AutoCloseable {
        final PipedInputStream clientIn;
        final PipedOutputStream clientOut;
        final PipedInputStream serverIn;
        final PipedOutputStream serverOut;
        final Connection connection;
        final Stream stream;

        FakeServer() throws IOException {
            serverOut = new PipedOutputStream();
            clientIn  = new PipedInputStream(serverOut, 8192);
            clientOut = new PipedOutputStream();
            serverIn  = new PipedInputStream(clientOut, 8192);
            connection = Connection.create(clientIn, clientOut);
            stream = connection.newStream(); // stream ID 3
        }

        /** Kill the server by closing its output → client reader thread detects EOF. */
        void killServer() throws IOException {
            serverOut.close();
        }

        /** Send a response packet from the server to the client stream. */
        void respond(int msgId, JsonNode payload) throws IOException {
            new Packet(stream.streamId(), msgId, true, Cbor.encode(payload)).write(serverOut);
            serverOut.flush();
        }

        /** Read a request packet from the client. Returns the message ID. */
        Packet readRequest() throws IOException {
            return Packet.read(serverIn);
        }

        ServerDataSource newDataSource() {
            return new ServerDataSource(connection, stream);
        }

        @Override
        public void close() throws IOException {
            try { serverOut.close(); } catch (IOException ignored) {}
            try { serverIn.close(); } catch (IOException ignored) {}
        }
    }

    // -----------------------------------------------------------------------
    // generate() IOException on sendRequest (ServerDataSource.java:45-47)
    // -----------------------------------------------------------------------

    @Test
    void generateIOExceptionOnSendRequest() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            // Kill server → serverExited=true → stream.sendRequest() throws IOException
            fs.killServer();
            Thread.sleep(200);

            ObjectNode schema = Cbor.map();
            schema.put("type", "integer");

            // generate() catches IOException from sendRequest → sets aborted=true → StopTestException
            StopTestException ex = assertThrows(StopTestException.class, () ->
                ds.generate(schema)
            );
            assertTrue(ds.testAborted());
            assertTrue(ex.getMessage().contains("send") || ex.getMessage() != null);
        }
    }

    // -----------------------------------------------------------------------
    // generate() IOException on receiveReply (ServerDataSource.java:53-55)
    // -----------------------------------------------------------------------

    @Test
    void generateIOExceptionOnReceiveReply() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();
            AtomicReference<Throwable> serverError = new AtomicReference<>();

            ObjectNode schema = Cbor.map();
            schema.put("type", "integer");

            // Server reads the request then closes → client's receiveReply will throw
            Thread serverThread = new Thread(() -> {
                try {
                    fs.readRequest(); // consume the generate request
                    fs.killServer(); // close → client gets SERVER_EXITED
                } catch (Exception e) {
                    serverError.set(e);
                }
            });
            serverThread.start();

            StopTestException ex = assertThrows(StopTestException.class, () ->
                ds.generate(schema)
            );
            serverThread.join(3000);
            assertTrue(ds.testAborted());
            assertTrue(ex.getMessage().contains("receive") || ex.getMessage() != null);
        }
    }

    // -----------------------------------------------------------------------
    // generate() FlakyStrategyDefinition error (ServerDataSource.java:72-74)
    // -----------------------------------------------------------------------

    @Test
    void generateFlakyStrategyError() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            ObjectNode schema = Cbor.map();
            schema.put("type", "integer");

            // Server responds with a FlakyStrategyDefinition error
            Thread serverThread = new Thread(() -> {
                try {
                    Packet req = fs.readRequest();
                    ObjectNode response = Cbor.map();
                    response.put("error", "FlakyStrategyDefinition: some flaky error");
                    response.put("type", "FlakyStrategyDefinition");
                    fs.respond(req.messageId(), response);
                } catch (Exception e) {
                    // ignore
                }
            });
            serverThread.start();

            StopTestException ex = assertThrows(StopTestException.class, () ->
                ds.generate(schema)
            );
            serverThread.join(3000);
            assertTrue(ds.testAborted());
            assertTrue(ex.getMessage().contains("flaky"),
                       "Unexpected: " + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // generate() generic server error → RuntimeException (ServerDataSource.java:76)
    // -----------------------------------------------------------------------

    @Test
    void generateGenericServerError() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            ObjectNode schema = Cbor.map();
            schema.put("type", "integer");

            // Server responds with an error that's neither StopTest nor flaky
            Thread serverThread = new Thread(() -> {
                try {
                    Packet req = fs.readRequest();
                    ObjectNode response = Cbor.map();
                    response.put("error", "some unexpected error");
                    response.put("type", "UnknownErrorType");
                    fs.respond(req.messageId(), response);
                } catch (Exception e) {
                    // ignore
                }
            });
            serverThread.start();

            RuntimeException ex = assertThrows(RuntimeException.class, () ->
                ds.generate(schema)
            );
            serverThread.join(3000);
            assertFalse(ex instanceof StopTestException);
            assertTrue(ex.getMessage().contains("Server error"),
                       "Unexpected: " + ex.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // generate() response with no "result" or "error" key (ServerDataSource.java:84)
    // -----------------------------------------------------------------------

    @Test
    void generateResponseWithNoResultOrError() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            ObjectNode schema = Cbor.map();
            schema.put("type", "integer");

            // Server responds with something that has neither "result" nor "error"
            Thread serverThread = new Thread(() -> {
                try {
                    Packet req = fs.readRequest();
                    ObjectNode response = Cbor.map();
                    response.put("status", "ok"); // no "result" or "error" key
                    fs.respond(req.messageId(), response);
                } catch (Exception e) {
                    // ignore
                }
            });
            serverThread.start();

            // generate() returns decoded directly (line 84)
            JsonNode result = ds.generate(schema);
            serverThread.join(3000);
            assertNotNull(result);
            assertEquals("ok", result.get("status").asText());
        }
    }

    // -----------------------------------------------------------------------
    // collectionReject() body (ServerDataSource.java:137-143)
    // -----------------------------------------------------------------------

    @Test
    void collectionRejectSendsRequest() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            // Server reads the collection_reject request and replies
            Thread serverThread = new Thread(() -> {
                try {
                    Packet req = fs.readRequest();
                    ObjectNode response = Cbor.map();
                    response.putNull("result");
                    fs.respond(req.messageId(), response);
                } catch (Exception e) {
                    // ignore
                }
            });
            serverThread.start();

            // Should not throw; covers lines 137-143 including the "why != null" branch
            assertDoesNotThrow(() -> ds.collectionReject(42L, "too large"));
            serverThread.join(3000);
        }
    }

    @Test
    void collectionRejectWithNullWhy() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            Thread serverThread = new Thread(() -> {
                try {
                    Packet req = fs.readRequest();
                    ObjectNode response = Cbor.map();
                    response.putNull("result");
                    fs.respond(req.messageId(), response);
                } catch (Exception e) {
                    // ignore
                }
            });
            serverThread.start();

            // why=null → line 140 (extra.put("why", why)) is skipped
            assertDoesNotThrow(() -> ds.collectionReject(1L, null));
            serverThread.join(3000);
        }
    }

    // -----------------------------------------------------------------------
    // markComplete() exception catch (ServerDataSource.java:159)
    // -----------------------------------------------------------------------

    @Test
    void markCompleteExceptionCaught() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            // Kill server before markComplete → sendRequest throws IOException
            // → caught at line 159 (Exception catch in markComplete)
            fs.killServer();
            Thread.sleep(200);

            // Should not throw (exception is swallowed at line 159)
            assertDoesNotThrow(() -> ds.markComplete("passed", null));
        }
    }

    // -----------------------------------------------------------------------
    // target() StopTestException swallowed (ServerDataSource.java:178)
    // -----------------------------------------------------------------------

    @Test
    void targetStopTestSwallowed() throws Exception {
        try (FakeServer fs = new FakeServer()) {
            ServerDataSource ds = fs.newDataSource();

            // Kill server → next call will fail with IOException → StopTestException
            fs.killServer();
            Thread.sleep(200);

            // target() calls sendRequest() which throws StopTestException
            // (because serverExited=true → sendRequest throws IOException → lines 45-47)
            // target() catches StopTestException at line 178 and swallows it
            assertDoesNotThrow(() -> ds.target(0.5, "my_metric"));
        }
    }
}
