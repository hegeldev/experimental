package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.protocol.Cbor;
import dev.hegel.protocol.Connection;
import dev.hegel.protocol.Stream;
import java.io.IOException;

/**
 * {@link DataSource} that communicates with the hegel-core server over a multiplexed {@link
 * Stream}.
 */
public class ServerDataSource implements DataSource {

  private final Connection connection;
  private final Stream stream;
  private boolean aborted = false;

  public ServerDataSource(Connection connection, Stream stream) {
    this.connection = connection;
    this.stream = stream;
  }

  // -----------------------------------------------------------------------
  // Core request/response
  // -----------------------------------------------------------------------

  private JsonNode sendRequest(String command, ObjectNode extra) throws StopTestException {
    if (aborted) {
      throw new StopTestException();
    }

    ObjectNode msg = Cbor.map();
    msg.put("command", command);
    if (extra != null) {
      msg.setAll(extra);
    }

    byte[] encoded = Cbor.encode(msg);
    int msgId;
    try {
      msgId = stream.sendRequest(encoded);
    } catch (IOException e) {
      aborted = true;
      throw new StopTestException("Failed to send command: " + e.getMessage());
    }

    byte[] responseBytes;
    try {
      responseBytes = stream.receiveReply(msgId);
    } catch (IOException e) {
      aborted = true;
      throw new StopTestException("Failed to receive response: " + e.getMessage());
    }

    JsonNode decoded = Cbor.decode(responseBytes);

    // Check for error responses
    if (decoded.isObject() && decoded.has("error")) {
      String errorMsg = decoded.get("error").toString();
      String errorType = decoded.has("type") ? decoded.get("type").asText("") : "";

      if (errorMsg.contains("overflow")
          || errorMsg.contains("StopTest")
          || errorType.contains("overflow")
          || errorType.contains("StopTest")) {
        stream.markClosed();
        aborted = true;
        throw new StopTestException("Server StopTest: " + errorMsg);
      }
      if (errorMsg.contains("FlakyStrategyDefinition") || errorMsg.contains("FlakyReplay")) {
        stream.markClosed();
        aborted = true;
        throw new StopTestException("Server flaky: " + errorMsg);
      }
      throw new RuntimeException("Server error (" + errorType + "): " + errorMsg);
    }

    // Unwrap {result: value} envelope
    if (decoded.isObject() && decoded.has("result")) {
      return decoded.get("result");
    }

    return decoded;
  }

  // -----------------------------------------------------------------------
  // DataSource implementation
  // -----------------------------------------------------------------------

  @Override
  public JsonNode generate(JsonNode schema) throws StopTestException {
    ObjectNode extra = Cbor.map();
    extra.set("schema", schema);
    return sendRequest("generate", extra);
  }

  @Override
  public void startSpan(long label) throws StopTestException {
    ObjectNode extra = Cbor.map();
    extra.put("label", label);
    sendRequest("start_span", extra);
  }

  @Override
  public void stopSpan(boolean discard) {
    try {
      ObjectNode extra = Cbor.map();
      extra.put("discard", discard);
      sendRequest("stop_span", extra);
    } catch (StopTestException e) {
      // Swallow — already aborted
    }
  }

  @Override
  public long newCollection(long minSize, Long maxSize) throws StopTestException {
    ObjectNode extra = Cbor.map();
    extra.put("min_size", minSize);
    if (maxSize != null) {
      extra.put("max_size", maxSize);
    }
    JsonNode result = sendRequest("new_collection", extra);
    return result.longValue();
  }

  @Override
  public boolean collectionMore(long collectionId) throws StopTestException {
    ObjectNode extra = Cbor.map();
    extra.put("collection_id", collectionId);
    JsonNode result = sendRequest("collection_more", extra);
    return result.booleanValue();
  }

  @Override
  public void collectionReject(long collectionId, String why) throws StopTestException {
    ObjectNode extra = Cbor.map();
    extra.put("collection_id", collectionId);
    if (why != null) {
      extra.put("why", why);
    }
    sendRequest("collection_reject", extra);
  }

  @Override
  public void markComplete(String status, String origin) {
    try {
      ObjectNode msg = Cbor.map();
      msg.put("command", "mark_complete");
      msg.put("status", status);
      if (origin != null) {
        msg.put("origin", origin);
      } else {
        msg.putNull("origin");
      }
      byte[] encoded = Cbor.encode(msg);
      int msgId = stream.sendRequest(encoded);
      stream.receiveReply(msgId); // consume the reply
    } catch (Exception e) {
      // Ignore errors during mark_complete
    } finally {
      stream.close();
    }
  }

  @Override
  public boolean testAborted() {
    return aborted;
  }

  @Override
  public void target(double value, String label) {
    ObjectNode extra = Cbor.map();
    extra.put("label", label);
    extra.put("value", value);
    try {
      sendRequest("target", extra);
    } catch (StopTestException e) {
      // target is an optional optimization hint; swallow errors
    }
  }
}
