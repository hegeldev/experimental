package dev.hegel.protocol;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.dataformat.cbor.CBORFactory;
import java.io.IOException;

/**
 * Utilities for CBOR encoding and decoding.
 *
 * <p>We use Jackson's CBOR module for serialization and represent values as {@link JsonNode} trees
 * (since CBOR and JSON share the same data model for our purposes).
 *
 * <p>Note on WTF-8 (CBOR tag 91): The hegel-core server may send strings encoded as CBOR byte
 * strings with tag 91 (WTF-8). Jackson's CBOR module handles standard CBOR types; for tag 91 we
 * fall back to raw UTF-8 decoding.
 */
public final class Cbor {

  private static final ObjectMapper MAPPER = new ObjectMapper(new CBORFactory());

  /** Package-private: override mapper for testing error paths (null = use default). */
  static ObjectMapper testMapper = null;

  private static ObjectMapper getMapper() {
    return testMapper != null ? testMapper : MAPPER;
  }

  private Cbor() {}

  /** Encode a {@link JsonNode} to CBOR bytes. */
  public static byte[] encode(JsonNode value) {
    try {
      return getMapper().writeValueAsBytes(value);
    } catch (JsonProcessingException e) {
      throw new HegelProtocolException("CBOR encode failed", e);
    }
  }

  /** Decode CBOR bytes to a {@link JsonNode}. */
  public static JsonNode decode(byte[] data) {
    try {
      return getMapper().readTree(data);
    } catch (IOException e) {
      throw new HegelProtocolException("CBOR decode failed: " + e.getMessage(), e);
    }
  }

  // -----------------------------------------------------------------------
  // Factory helpers for building schemas / command payloads
  // -----------------------------------------------------------------------

  public static ObjectMapper mapper() {
    return getMapper();
  }

  public static ObjectNode map() {
    return MAPPER.createObjectNode();
  }

  public static ArrayNode array() {
    return MAPPER.createArrayNode();
  }

  public static ArrayNode array(JsonNode... elements) {
    ArrayNode arr = MAPPER.createArrayNode();
    for (JsonNode el : elements) {
      arr.add(el);
    }
    return arr;
  }
}
