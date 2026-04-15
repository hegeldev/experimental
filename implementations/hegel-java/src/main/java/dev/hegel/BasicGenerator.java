package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.BinaryNode;
import java.util.Optional;
import java.util.function.Function;

/**
 * A generator that can describe what it needs as a CBOR schema.
 *
 * <p>A basic generator has:
 *
 * <ul>
 *   <li>A <em>raw schema</em>: sent to the server to generate a raw value.
 *   <li>An optional <em>transform</em>: applied client-side to the raw server value.
 * </ul>
 *
 * <p>Applying {@link #map(java.util.function.Function)} to a basic generator preserves basic-ness:
 * the new transform is the composition of the existing transform and the mapping function, and the
 * schema is unchanged.
 *
 * @param <T> the type of values this generator produces
 */
public class BasicGenerator<T> implements Generator<T> {

  private final JsonNode schema;
  private final Function<JsonNode, T> transform;

  /**
   * Create a basic generator with a schema and a transform.
   *
   * @param schema CBOR schema sent to the server
   * @param transform function applied to the raw server value
   */
  public BasicGenerator(JsonNode schema, Function<JsonNode, T> transform) {
    this.schema = schema;
    this.transform = transform;
  }

  /**
   * Create a basic generator with a schema and identity transform. The {@link #generate} method
   * will return the raw server value cast to {@code T}.
   */
  @SuppressWarnings("unchecked")
  public static <T> BasicGenerator<T> withSchema(JsonNode schema) {
    return new BasicGenerator<>(schema, node -> (T) nodeToObject(node));
  }

  /** Return the raw CBOR schema. */
  public JsonNode schema() {
    return schema;
  }

  /** Return the transform function. */
  public Function<JsonNode, T> transform() {
    return transform;
  }

  @Override
  public T generate(TestCase tc) {
    JsonNode raw = tc.generateRaw(schema);
    return transform.apply(raw);
  }

  @Override
  public Optional<BasicGenerator<T>> asBasic() {
    return Optional.of(this);
  }

  /**
   * Create a new basic generator that applies {@code f} after this generator's transform. The
   * schema is unchanged.
   */
  public <U> BasicGenerator<U> mapBasic(java.util.function.Function<T, U> f) {
    Function<JsonNode, T> existing = this.transform;
    return new BasicGenerator<>(schema, node -> f.apply(existing.apply(node)));
  }

  // -----------------------------------------------------------------------
  // JSON node → Java object conversion
  // -----------------------------------------------------------------------

  /**
   * Convert a {@link JsonNode} to a plain Java object. Used by identity-transform basic generators.
   */
  public static Object nodeToObject(JsonNode node) {
    if (node == null || node.isNull()) return null;
    if (node.isBoolean()) return node.booleanValue();
    if (node.isIntegralNumber()) {
      long v = node.longValue();
      if (v >= Integer.MIN_VALUE && v <= Integer.MAX_VALUE) {
        return (int) v;
      }
      return v;
    }
    if (node.isFloatingPointNumber()) return node.doubleValue();
    if (node.isTextual()) return node.textValue();
    if (node.isBinary()) {
      return ((BinaryNode) node).binaryValue();
    }
    if (node.isArray()) {
      java.util.List<Object> list = new java.util.ArrayList<>();
      for (JsonNode el : node) {
        list.add(nodeToObject(el));
      }
      return list;
    }
    if (node.isObject()) {
      java.util.Map<String, Object> map = new java.util.LinkedHashMap<>();
      node.fields().forEachRemaining(e -> map.put(e.getKey(), nodeToObject(e.getValue())));
      return map;
    }
    return node.toString();
  }
}
