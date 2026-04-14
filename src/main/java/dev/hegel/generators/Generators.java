package dev.hegel.generators;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.hegel.BasicGenerator;
import dev.hegel.Generator;
import dev.hegel.Labels;
import dev.hegel.TestCase;
import dev.hegel.protocol.Cbor;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;

/**
 * Factory methods for all built-in Hegel generators.
 *
 * <p>Import statically for the cleanest usage:
 * <pre>{@code
 * import static dev.hegel.generators.Generators.*;
 *
 * Hegel.test("my test", tc -> {
 *     int x = tc.draw(integers());
 *     List<String> words = tc.draw(lists(text()));
 * });
 * }</pre>
 */
public final class Generators {

    private Generators() {}

    // -----------------------------------------------------------------------
    // Integers
    // -----------------------------------------------------------------------

    /**
     * Generate integer values.
     * Defaults to the full {@code long} range.
     */
    public static IntegerGenerator integers() {
        return new IntegerGenerator(null, null);
    }

    /** Generate integers in the range [{@code min}, {@code max}]. */
    public static IntegerGenerator integers(long min, long max) {
        return new IntegerGenerator(min, max);
    }

    /** Builder for integer generators. */
    public static final class IntegerGenerator implements Generator<Long> {
        private final Long min;
        private final Long max;

        IntegerGenerator(Long min, Long max) {
            this.min = min;
            this.max = max;
        }

        /** Set the minimum value (inclusive). */
        public IntegerGenerator minValue(long min) {
            return new IntegerGenerator(min, this.max);
        }

        /** Set the maximum value (inclusive). */
        public IntegerGenerator maxValue(long max) {
            return new IntegerGenerator(this.min, max);
        }

        private ObjectNode buildSchema() {
            long lo = min != null ? min : Long.MIN_VALUE;
            long hi = max != null ? max : Long.MAX_VALUE;
            if (lo > hi) throw new IllegalArgumentException("minValue > maxValue");
            ObjectNode schema = Cbor.map();
            schema.put("type", "integer");
            schema.put("min_value", lo);
            schema.put("max_value", hi);
            return schema;
        }

        @Override
        public Long generate(TestCase tc) {
            return asBasic().orElseThrow().generate(tc);
        }

        @Override
        public Optional<BasicGenerator<Long>> asBasic() {
            ObjectNode schema = buildSchema();
            return Optional.of(new BasicGenerator<>(schema, node -> {
                if (node.isIntegralNumber()) return node.longValue();
                return node.asLong();
            }));
        }

        // Convenience: integer range as int (truncating)
        public Generator<Integer> asInt() {
            return this.map(Long::intValue);
        }
    }

    // -----------------------------------------------------------------------
    // Floats
    // -----------------------------------------------------------------------

    /**
     * Generate floating-point values (64-bit).
     * By default, allows NaN and infinity only when no bounds are set.
     */
    public static FloatGenerator floats() {
        return new FloatGenerator();
    }

    /** Builder for float generators. */
    public static final class FloatGenerator implements Generator<Double> {
        private Double min;
        private Double max;
        private boolean excludeMin = false;
        private boolean excludeMax = false;
        private Boolean allowNan;
        private Boolean allowInfinity;

        private FloatGenerator() {}

        private FloatGenerator(FloatGenerator other) {
            this.min = other.min;
            this.max = other.max;
            this.excludeMin = other.excludeMin;
            this.excludeMax = other.excludeMax;
            this.allowNan = other.allowNan;
            this.allowInfinity = other.allowInfinity;
        }

        public FloatGenerator minValue(double min) {
            FloatGenerator g = new FloatGenerator(this); g.min = min; return g;
        }
        public FloatGenerator maxValue(double max) {
            FloatGenerator g = new FloatGenerator(this); g.max = max; return g;
        }
        public FloatGenerator excludeMin(boolean v) {
            FloatGenerator g = new FloatGenerator(this); g.excludeMin = v; return g;
        }
        public FloatGenerator excludeMax(boolean v) {
            FloatGenerator g = new FloatGenerator(this); g.excludeMax = v; return g;
        }
        public FloatGenerator allowNan(boolean v) {
            FloatGenerator g = new FloatGenerator(this); g.allowNan = v; return g;
        }
        public FloatGenerator allowInfinity(boolean v) {
            FloatGenerator g = new FloatGenerator(this); g.allowInfinity = v; return g;
        }

        private ObjectNode buildSchema() {
            boolean hasMin = min != null;
            boolean hasMax = max != null;
            boolean nan = allowNan != null ? allowNan : (!hasMin && !hasMax);
            boolean inf = allowInfinity != null ? allowInfinity : (!hasMin || !hasMax);

            ObjectNode schema = Cbor.map();
            schema.put("type", "float");
            schema.put("width", 64);
            schema.put("allow_nan", nan);
            schema.put("allow_infinity", inf);
            if (hasMin) {
                schema.put("min_value", min);
                schema.put("exclude_min", excludeMin);
            }
            if (hasMax) {
                schema.put("max_value", max);
                schema.put("exclude_max", excludeMax);
            }
            return schema;
        }

        @Override
        public Double generate(TestCase tc) {
            return asBasic().orElseThrow().generate(tc);
        }

        @Override
        public Optional<BasicGenerator<Double>> asBasic() {
            ObjectNode schema = buildSchema();
            return Optional.of(new BasicGenerator<>(schema, node -> {
                if (node.isNull()) return Double.NaN;
                if (node.isFloatingPointNumber()) return node.doubleValue();
                if (node.isIntegralNumber()) return (double) node.longValue();
                double v = node.asDouble();
                return v;
            }));
        }
    }

    // -----------------------------------------------------------------------
    // Booleans
    // -----------------------------------------------------------------------

    /** Generate boolean values. */
    public static Generator<Boolean> booleans() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "boolean");
        return new BasicGenerator<>(schema, JsonNode::booleanValue);
    }

    // -----------------------------------------------------------------------
    // Text / Strings
    // -----------------------------------------------------------------------

    /** Generate Unicode text strings. */
    public static TextGenerator text() {
        return new TextGenerator();
    }

    /** Builder for text generators. */
    public static final class TextGenerator implements Generator<String> {
        private int minSize = 0;
        private Integer maxSize;
        private String codec;

        private TextGenerator() {}
        private TextGenerator(TextGenerator other) {
            this.minSize = other.minSize;
            this.maxSize = other.maxSize;
            this.codec = other.codec;
        }

        public TextGenerator minSize(int min) { TextGenerator g = new TextGenerator(this); g.minSize = min; return g; }
        public TextGenerator maxSize(int max) { TextGenerator g = new TextGenerator(this); g.maxSize = max; return g; }
        public TextGenerator codec(String codec) { TextGenerator g = new TextGenerator(this); g.codec = codec; return g; }
        public TextGenerator ascii() { return codec("ascii"); }

        private ObjectNode buildSchema() {
            ObjectNode schema = Cbor.map();
            schema.put("type", "string");
            schema.put("min_size", minSize);
            if (maxSize != null) schema.put("max_size", maxSize);
            if (codec != null) schema.put("codec", codec);
            return schema;
        }

        @Override
        public String generate(TestCase tc) {
            return asBasic().orElseThrow().generate(tc);
        }

        @Override
        public Optional<BasicGenerator<String>> asBasic() {
            ObjectNode schema = buildSchema();
            return Optional.of(new BasicGenerator<>(schema, node -> {
                if (node.isTextual()) return node.textValue();
                // Handle WTF-8 / binary node that might be returned for strings
                if (node.isBinary()) {
                    try {
                        return new String(node.binaryValue(), java.nio.charset.StandardCharsets.UTF_8);
                    } catch (Exception e) {
                        return node.asText();
                    }
                }
                return node.asText();
            }));
        }
    }

    // -----------------------------------------------------------------------
    // Binary
    // -----------------------------------------------------------------------

    /** Generate binary data (byte arrays). */
    public static BinaryGenerator binary() {
        return new BinaryGenerator();
    }

    /** Builder for binary generators. */
    public static final class BinaryGenerator implements Generator<byte[]> {
        private int minSize = 0;
        private Integer maxSize;

        private BinaryGenerator() {}
        private BinaryGenerator(BinaryGenerator other) {
            this.minSize = other.minSize;
            this.maxSize = other.maxSize;
        }

        public BinaryGenerator minSize(int min) { BinaryGenerator g = new BinaryGenerator(this); g.minSize = min; return g; }
        public BinaryGenerator maxSize(int max) { BinaryGenerator g = new BinaryGenerator(this); g.maxSize = max; return g; }

        private ObjectNode buildSchema() {
            ObjectNode schema = Cbor.map();
            schema.put("type", "binary");
            schema.put("min_size", minSize);
            if (maxSize != null) schema.put("max_size", maxSize);
            return schema;
        }

        @Override
        public byte[] generate(TestCase tc) {
            return asBasic().orElseThrow().generate(tc);
        }

        @Override
        public Optional<BasicGenerator<byte[]>> asBasic() {
            ObjectNode schema = buildSchema();
            return Optional.of(new BasicGenerator<>(schema, node -> {
                if (node.isBinary()) {
                    try {
                        return node.binaryValue();
                    } catch (Exception e) {
                        return new byte[0];
                    }
                }
                // Fallback: treat textual nodes as UTF-8 bytes
                if (node.isTextual()) {
                    return node.textValue().getBytes(java.nio.charset.StandardCharsets.UTF_8);
                }
                return new byte[0];
            }));
        }
    }

    // -----------------------------------------------------------------------
    // just / sampledFrom
    // -----------------------------------------------------------------------

    /**
     * Always generate the same constant value.
     *
     * <p>Basic: schema is {@code {"constant": null}}, transform always returns the value.
     */
    public static <T> Generator<T> just(T value) {
        ObjectNode schema = Cbor.map();
        schema.putNull("constant");
        return new BasicGenerator<>(schema, node -> value);
    }

    /**
     * Sample uniformly from a fixed list of values.
     *
     * <p>Basic: generates an index, transform returns {@code values[index]}.
     */
    @SafeVarargs
    public static <T> Generator<T> sampledFrom(T... values) {
        return sampledFrom(Arrays.asList(values));
    }

    public static <T> Generator<T> sampledFrom(List<T> values) {
        if (values.isEmpty()) throw new IllegalArgumentException("sampledFrom: values must not be empty");
        ObjectNode schema = Cbor.map();
        schema.put("type", "integer");
        schema.put("min_value", 0);
        schema.put("max_value", values.size() - 1);
        List<T> copy = List.copyOf(values);
        return new BasicGenerator<>(schema, node -> copy.get((int) node.longValue()));
    }

    // -----------------------------------------------------------------------
    // Lists
    // -----------------------------------------------------------------------

    /** Generate lists of elements produced by {@code elements}. */
    public static <T> ListGenerator<T> lists(Generator<T> elements) {
        return new ListGenerator<>(elements, 0, null);
    }

    /** Builder for list generators. */
    public static final class ListGenerator<T> implements Generator<List<T>> {
        private final Generator<T> elements;
        private final int minSize;
        private final Integer maxSize;

        ListGenerator(Generator<T> elements, int minSize, Integer maxSize) {
            this.elements = elements;
            this.minSize = minSize;
            this.maxSize = maxSize;
        }

        public ListGenerator<T> minSize(int min) {
            return new ListGenerator<>(elements, min, this.maxSize);
        }

        public ListGenerator<T> maxSize(int max) {
            return new ListGenerator<>(elements, this.minSize, max);
        }

        @Override
        public List<T> generate(TestCase tc) {
            Optional<BasicGenerator<T>> basic = elements.asBasic();
            if (basic.isPresent()) {
                return generateBasic(tc, basic.get());
            } else {
                return generateCompositional(tc);
            }
        }

        @Override
        public Optional<BasicGenerator<List<T>>> asBasic() {
            Optional<BasicGenerator<T>> basic = elements.asBasic();
            if (basic.isEmpty()) return Optional.empty();

            BasicGenerator<T> bg = basic.get();
            ObjectNode schema = Cbor.map();
            schema.put("type", "list");
            schema.set("elements", bg.schema());
            schema.put("min_size", minSize);
            if (maxSize != null) schema.put("max_size", maxSize);

            Function<JsonNode, T> transform = bg.transform();
            return Optional.of(new BasicGenerator<>(schema, node -> {
                List<T> result = new ArrayList<>();
                for (JsonNode el : node) {
                    result.add(transform.apply(el));
                }
                return result;
            }));
        }

        private List<T> generateBasic(TestCase tc, BasicGenerator<T> bg) {
            // Use schema composition path
            return asBasic().orElseThrow().generate(tc);
        }

        private List<T> generateCompositional(TestCase tc) {
            // Use collection protocol
            tc.startSpan(Labels.LIST);
            try {
                long maxSizeLong = maxSize != null ? maxSize : Long.MAX_VALUE;
                long collectionId = tc.newCollection(minSize, maxSize != null ? (long) maxSize : null);
                List<T> result = new ArrayList<>();
                while (tc.collectionMore(collectionId)) {
                    tc.startSpan(Labels.LIST_ELEMENT);
                    try {
                        T el = elements.generate(tc);
                        result.add(el);
                    } finally {
                        tc.stopSpan(false);
                    }
                }
                return result;
            } finally {
                tc.stopSpan(false);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Maps (dictionaries)
    // -----------------------------------------------------------------------

    /** Generate maps with keys from {@code keys} and values from {@code values}. */
    public static <K, V> MapGenerator<K, V> maps(Generator<K> keys, Generator<V> values) {
        return new MapGenerator<>(keys, values, 0, null);
    }

    /** Builder for map generators. */
    public static final class MapGenerator<K, V> implements Generator<Map<K, V>> {
        private final Generator<K> keys;
        private final Generator<V> values;
        private final int minSize;
        private final Integer maxSize;

        MapGenerator(Generator<K> keys, Generator<V> values, int minSize, Integer maxSize) {
            this.keys = keys;
            this.values = values;
            this.minSize = minSize;
            this.maxSize = maxSize;
        }

        public MapGenerator<K, V> minSize(int min) {
            return new MapGenerator<>(keys, values, min, this.maxSize);
        }
        public MapGenerator<K, V> maxSize(int max) {
            return new MapGenerator<>(keys, values, this.minSize, max);
        }

        @Override
        public Map<K, V> generate(TestCase tc) {
            Optional<BasicGenerator<Map<K, V>>> basic = asBasic();
            if (basic.isPresent()) {
                return basic.get().generate(tc);
            }
            return generateCompositional(tc);
        }

        @Override
        public Optional<BasicGenerator<Map<K, V>>> asBasic() {
            Optional<BasicGenerator<K>> keyBasic = keys.asBasic();
            Optional<BasicGenerator<V>> valBasic = values.asBasic();
            if (keyBasic.isEmpty() || valBasic.isEmpty()) return Optional.empty();

            BasicGenerator<K> kb = keyBasic.get();
            BasicGenerator<V> vb = valBasic.get();

            ObjectNode schema = Cbor.map();
            schema.put("type", "dict");
            schema.set("keys", kb.schema());
            schema.set("values", vb.schema());
            schema.put("min_size", minSize);
            if (maxSize != null) schema.put("max_size", maxSize);

            Function<JsonNode, K> kt = kb.transform();
            Function<JsonNode, V> vt = vb.transform();

            return Optional.of(new BasicGenerator<>(schema, node -> {
                // Server returns a list of [key, value] pairs
                Map<K, V> result = new LinkedHashMap<>();
                for (JsonNode pair : node) {
                    K key = kt.apply(pair.get(0));
                    V val = vt.apply(pair.get(1));
                    result.put(key, val);
                }
                return result;
            }));
        }

        private Map<K, V> generateCompositional(TestCase tc) {
            tc.startSpan(Labels.MAP);
            try {
                long collectionId = tc.newCollection(minSize, maxSize != null ? (long) maxSize : null);
                Map<K, V> result = new LinkedHashMap<>();
                while (tc.collectionMore(collectionId)) {
                    tc.startSpan(Labels.MAP_ENTRY);
                    try {
                        K key = keys.generate(tc);
                        V val = values.generate(tc);
                        result.put(key, val);
                    } finally {
                        tc.stopSpan(false);
                    }
                }
                return result;
            } finally {
                tc.stopSpan(false);
            }
        }
    }

    // -----------------------------------------------------------------------
    // oneOf
    // -----------------------------------------------------------------------

    /**
     * Choose one of the given generators, each with equal probability.
     */
    @SafeVarargs
    public static <T> Generator<T> oneOf(Generator<T>... gens) {
        return oneOf(Arrays.asList(gens));
    }

    @SuppressWarnings("unchecked")
    public static <T> Generator<T> oneOf(List<Generator<T>> gens) {
        if (gens.isEmpty()) throw new IllegalArgumentException("oneOf: no generators provided");
        if (gens.size() == 1) return gens.get(0);

        // Check if all generators are basic
        List<BasicGenerator<T>> basics = new ArrayList<>();
        boolean allBasic = true;
        for (Generator<T> g : gens) {
            Optional<BasicGenerator<T>> b = g.asBasic();
            if (b.isPresent()) {
                basics.add(b.get());
            } else {
                allBasic = false;
                break;
            }
        }

        if (allBasic) {
            // Check if any have transforms
            boolean anyTransforms = basics.stream().anyMatch(b -> {
                // Check if transform is identity by introspection isn't possible,
                // so we use the tagged tuple approach for all basic oneOf
                return true;
            });

            // Use tagged tuples approach: {one_of: [{type: tuple, elements: [{constant: 0}, schema1]}, ...]}
            ArrayNode oneOfArr = Cbor.array();
            List<Function<JsonNode, T>> transforms = new ArrayList<>();

            for (int i = 0; i < basics.size(); i++) {
                BasicGenerator<T> b = basics.get(i);
                ObjectNode tupleSchema = Cbor.map();
                tupleSchema.put("type", "tuple");
                ArrayNode elements = Cbor.array();
                ObjectNode tagSchema = Cbor.map();
                tagSchema.put("constant", i);
                elements.add(tagSchema);
                elements.add(b.schema());
                tupleSchema.set("elements", elements);
                oneOfArr.add(tupleSchema);
                transforms.add(b.transform());
            }

            ObjectNode schema = Cbor.map();
            schema.set("one_of", oneOfArr);

            List<Function<JsonNode, T>> finalTransforms = transforms;
            return new BasicGenerator<>(schema, node -> {
                // node is [tag, value]
                int tag = node.get(0).intValue();
                JsonNode value = node.get(1);
                return finalTransforms.get(tag).apply(value);
            });
        }

        // Non-basic: generate an index, then delegate
        List<Generator<T>> gensCopy = List.copyOf(gens);
        Generator<Long> indexGen = integers(0, gens.size() - 1);
        return tc -> {
            tc.startSpan(Labels.ONE_OF);
            try {
                long idx = indexGen.generate(tc);
                return gensCopy.get((int) idx).generate(tc);
            } finally {
                tc.stopSpan(false);
            }
        };
    }

    // -----------------------------------------------------------------------
    // optional
    // -----------------------------------------------------------------------

    /** Generate an optional value: either {@code null} or a value from {@code element}. */
    public static <T> Generator<T> optional(Generator<T> element) {
        // Implemented as oneOf(just(null), element) — but Java generics require T to be nullable
        @SuppressWarnings("unchecked")
        Generator<T> justNull = (Generator<T>) just((Object) null);
        return oneOf(List.of(justNull, element));
    }

    // -----------------------------------------------------------------------
    // Format generators
    // -----------------------------------------------------------------------

    /** Generate email addresses. */
    public static Generator<String> emails() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "email");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate URLs. */
    public static Generator<String> urls() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "url");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate domain names. */
    public static Generator<String> domains() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "domain");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate IPv4 addresses as strings. */
    public static Generator<String> ipv4Addresses() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "ipv4");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate IPv6 addresses as strings. */
    public static Generator<String> ipv6Addresses() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "ipv6");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate IPv4 or IPv6 addresses. */
    public static Generator<String> ipAddresses() {
        return oneOf(ipv4Addresses(), ipv6Addresses());
    }

    /** Generate dates in ISO 8601 format. */
    public static Generator<String> dates() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "date");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate times in ISO 8601 format. */
    public static Generator<String> times() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "time");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate datetimes in ISO 8601 format. */
    public static Generator<String> datetimes() {
        ObjectNode schema = Cbor.map();
        schema.put("type", "datetime");
        return new BasicGenerator<>(schema, JsonNode::asText);
    }

    /** Generate strings matching the given regular expression. */
    public static Generator<String> fromRegex(String pattern) {
        return fromRegex(pattern, false);
    }

    /** Generate strings matching the given regular expression. */
    public static Generator<String> fromRegex(String pattern, boolean fullmatch) {
        ObjectNode schema = Cbor.map();
        schema.put("type", "regex");
        schema.put("pattern", pattern);
        schema.put("fullmatch", fullmatch);
        return new BasicGenerator<>(schema, JsonNode::asText);
    }
}
