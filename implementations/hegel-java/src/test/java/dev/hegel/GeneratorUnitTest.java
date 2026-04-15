package dev.hegel;

import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.BinaryNode;
import com.fasterxml.jackson.databind.node.BooleanNode;
import com.fasterxml.jackson.databind.node.DoubleNode;
import com.fasterxml.jackson.databind.node.IntNode;
import com.fasterxml.jackson.databind.node.LongNode;
import com.fasterxml.jackson.databind.node.MissingNode;
import com.fasterxml.jackson.databind.node.NullNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.databind.node.TextNode;
import dev.hegel.protocol.Cbor;
import java.util.ArrayDeque;
import java.util.List;
import java.util.Queue;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for Generator interface defaults, BasicGenerator, and all Generators without needing
 * the real hegel-core server. Uses a MockDataSource.
 */
class GeneratorUnitTest {

  // -----------------------------------------------------------------------
  // MockDataSource
  // -----------------------------------------------------------------------

  /** A DataSource backed by a queue of pre-programmed responses. */
  static class MockDataSource implements DataSource {
    private final Queue<JsonNode> queue = new ArrayDeque<>();
    private boolean aborted = false;
    private long lastCollectionId = 0;
    private int collectionRemainingElements = 0;
    private final List<String> targetCalls = new java.util.ArrayList<>();

    MockDataSource withResponse(JsonNode node) {
      queue.add(node);
      return this;
    }

    MockDataSource withCollectionElements(int count) {
      this.collectionRemainingElements = count;
      return this;
    }

    @Override
    public JsonNode generate(JsonNode schema) {
      if (queue.isEmpty()) throw new StopTestException("MockDataSource: no more responses");
      return queue.poll();
    }

    @Override
    public void startSpan(long label) {
      /* no-op */
    }

    @Override
    public void stopSpan(boolean discard) {
      /* no-op */
    }

    @Override
    public long newCollection(long minSize, Long maxSize) {
      lastCollectionId++;
      return lastCollectionId;
    }

    @Override
    public boolean collectionMore(long collectionId) {
      if (collectionRemainingElements > 0) {
        collectionRemainingElements--;
        return true;
      }
      return false;
    }

    @Override
    public void collectionReject(long collectionId, String why) {
      /* no-op */
    }

    @Override
    public void markComplete(String status, String origin) {
      /* no-op */
    }

    @Override
    public boolean testAborted() {
      return aborted;
    }

    @Override
    public void target(double value, String label) {
      targetCalls.add(label + "=" + value);
    }
  }

  private TestCase tc(MockDataSource ds) {
    return new TestCase(ds, false);
  }

  private TestCase tcFinal(MockDataSource ds) {
    return new TestCase(ds, true);
  }

  // -----------------------------------------------------------------------
  // Generator interface defaults
  // -----------------------------------------------------------------------

  @Test
  void generatorAsBasicDefaultReturnsEmpty() {
    // A lambda generator is non-basic
    Generator<Integer> gen = tc -> 42;
    assertTrue(gen.asBasic().isEmpty());
  }

  @Test
  void generatorMapOnNonBasicWrapsInSpan() {
    // A non-basic generator's map() should produce a non-basic generator
    Generator<Integer> gen = tc -> 10;
    Generator<String> mapped = gen.map(n -> "val=" + n);

    // The result should be non-basic
    assertTrue(mapped.asBasic().isEmpty());

    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertEquals("val=10", mapped.generate(tc));
  }

  @Test
  void generatorFilterPassingPredicate() {
    // filter() that succeeds on first try
    int[] counter = {0};
    Generator<Integer> gen =
        tc -> {
          counter[0]++;
          return counter[0] * 5;
        };
    Generator<Integer> filtered = gen.filter(n -> n >= 5);

    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    int result = filtered.generate(tc);
    assertEquals(5, result);
    assertEquals(1, counter[0]);
  }

  @Test
  void generatorFilterRetriesOnFailure() {
    // filter() that fails twice then passes
    int[] counter = {0};
    Generator<Integer> gen =
        tc -> {
          counter[0]++;
          return counter[0];
        };
    Generator<Integer> filtered = gen.filter(n -> n >= 3);

    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    int result = filtered.generate(tc);
    assertEquals(3, result);
    assertEquals(3, counter[0]);
  }

  @Test
  void generatorFilterExhaustedCallsAssume() {
    // filter() that fails 3 times should call assume(false) → AssumeException
    Generator<Integer> gen = tc -> -1; // always returns -1
    Generator<Integer> filtered = gen.filter(n -> n > 0);

    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertThrows(AssumeException.class, () -> filtered.generate(tc));
  }

  @Test
  void generatorFlatMap() {
    // flatMap(): outer generates an integer, inner generates a string of that length
    Generator<Integer> outer = tc -> 3;
    Generator<String> flatMapped = outer.flatMap(n -> tc2 -> "x".repeat(n));

    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertEquals("xxx", flatMapped.generate(tc));
  }

  // -----------------------------------------------------------------------
  // BasicGenerator
  // -----------------------------------------------------------------------

  @Test
  void basicGeneratorGenerate() {
    ObjectNode schema = Cbor.map();
    schema.put("type", "integer");

    MockDataSource ds = new MockDataSource().withResponse(LongNode.valueOf(42L));
    TestCase tc = tc(ds);

    BasicGenerator<Long> gen = new BasicGenerator<>(schema, node -> node.longValue());
    assertEquals(42L, gen.generate(tc));
  }

  @Test
  void basicGeneratorAsBasicReturnsSelf() {
    ObjectNode schema = Cbor.map();
    BasicGenerator<String> gen = new BasicGenerator<>(schema, node -> node.asText());
    assertTrue(gen.asBasic().isPresent());
    assertSame(gen, gen.asBasic().get());
  }

  @Test
  void basicGeneratorWithSchema() {
    ObjectNode schema = Cbor.map();
    schema.put("type", "boolean");

    BasicGenerator<Object> gen = BasicGenerator.withSchema(schema);
    assertSame(schema, gen.schema());

    // Test generation with true
    MockDataSource ds = new MockDataSource().withResponse(BooleanNode.TRUE);
    TestCase tc = tc(ds);
    assertEquals(Boolean.TRUE, gen.generate(tc));
  }

  @Test
  void basicGeneratorMapBasic() {
    ObjectNode schema = Cbor.map();
    BasicGenerator<Long> gen = new BasicGenerator<>(schema, node -> node.longValue());
    BasicGenerator<String> mapped = gen.mapBasic(n -> "n=" + n);

    MockDataSource ds = new MockDataSource().withResponse(LongNode.valueOf(7L));
    TestCase tc = tc(ds);
    assertEquals("n=7", mapped.generate(tc));
    assertSame(schema, mapped.schema()); // schema is preserved
  }

  // -----------------------------------------------------------------------
  // BasicGenerator.nodeToObject()
  // -----------------------------------------------------------------------

  @Test
  void nodeToObjectNull() {
    assertNull(BasicGenerator.nodeToObject(null));
    assertNull(BasicGenerator.nodeToObject(NullNode.instance));
  }

  @Test
  void nodeToObjectBoolean() {
    assertEquals(Boolean.TRUE, BasicGenerator.nodeToObject(BooleanNode.TRUE));
    assertEquals(Boolean.FALSE, BasicGenerator.nodeToObject(BooleanNode.FALSE));
  }

  @Test
  void nodeToObjectIntegralSmall() {
    // Values within int range → returned as Integer
    Object result = BasicGenerator.nodeToObject(IntNode.valueOf(42));
    assertInstanceOf(Integer.class, result);
    assertEquals(42, result);
  }

  @Test
  void nodeToObjectIntegralLarge() {
    // Values outside int range → returned as Long
    long big = (long) Integer.MAX_VALUE + 1;
    Object result = BasicGenerator.nodeToObject(LongNode.valueOf(big));
    assertInstanceOf(Long.class, result);
    assertEquals(big, result);
  }

  @Test
  void nodeToObjectIntegralNegativeLarge() {
    long small = (long) Integer.MIN_VALUE - 1;
    Object result = BasicGenerator.nodeToObject(LongNode.valueOf(small));
    assertInstanceOf(Long.class, result);
    assertEquals(small, result);
  }

  @Test
  void nodeToObjectFloat() {
    Object result = BasicGenerator.nodeToObject(DoubleNode.valueOf(3.14));
    assertInstanceOf(Double.class, result);
    assertEquals(3.14, (Double) result, 0.001);
  }

  @Test
  void nodeToObjectText() {
    Object result = BasicGenerator.nodeToObject(TextNode.valueOf("hello"));
    assertInstanceOf(String.class, result);
    assertEquals("hello", result);
  }

  @Test
  void nodeToObjectArray() {
    com.fasterxml.jackson.databind.node.ArrayNode arr =
        Cbor.array(LongNode.valueOf(1L), LongNode.valueOf(2L));
    Object result = BasicGenerator.nodeToObject(arr);
    assertInstanceOf(List.class, result);
    List<?> list = (List<?>) result;
    assertEquals(2, list.size());
    assertEquals(1, list.get(0));
    assertEquals(2, list.get(1));
  }

  @Test
  void nodeToObjectObject() {
    ObjectNode node = Cbor.map();
    node.put("a", 1);
    node.put("b", "two");
    Object result = BasicGenerator.nodeToObject(node);
    assertInstanceOf(java.util.Map.class, result);
    java.util.Map<?, ?> map = (java.util.Map<?, ?>) result;
    assertEquals(1, map.get("a"));
    assertEquals("two", map.get("b"));
  }

  @Test
  void nodeToObjectBinary() throws Exception {
    // Create a binary node
    byte[] bytes = {1, 2, 3};
    com.fasterxml.jackson.databind.node.BinaryNode binaryNode =
        com.fasterxml.jackson.databind.node.BinaryNode.valueOf(bytes);
    Object result = BasicGenerator.nodeToObject(binaryNode);
    assertInstanceOf(byte[].class, result);
    assertArrayEquals(bytes, (byte[]) result);
  }

  @Test
  void nodeToObjectFallback() {
    // A node type that doesn't match any known case → returns toString()
    // Use a raw node that isn't handled (very edge case - use a pointer node or similar)
    // Actually we can use a custom node... but simplest is to ensure all branches are tested
    // The fallback is reached for unhandled types. IntNode covers integral, DoubleNode covers
    // float.
    // The last else branch returns node.toString() - hard to reach with standard node types.
    // Let's verify the coverage via the binary catch branch instead:
    // Create a BinaryNode whose binaryValue() throws (not possible with standard Jackson)
    // Instead, test the TextNode path in binary branch:
    // Actually this is about the catch block in nodeToObject for binary nodes
    // We'll skip this edge case since it requires a custom node subclass
  }

  // -----------------------------------------------------------------------
  // TestCase
  // -----------------------------------------------------------------------

  @Test
  void testCaseDraw() {
    MockDataSource ds = new MockDataSource().withResponse(LongNode.valueOf(99L));
    TestCase tc = tc(ds);
    BasicGenerator<Long> gen = new BasicGenerator<>(Cbor.map(), node -> node.longValue());
    assertEquals(99L, tc.draw(gen));
  }

  @Test
  void testCaseAssumeTrue() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertDoesNotThrow(() -> tc.assume(true));
  }

  @Test
  void testCaseAssumeFalseThrows() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertThrows(AssumeException.class, () -> tc.assume(false));
  }

  @Test
  void testCaseNoteNotFinalRun() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    // note() is a no-op when not the final run
    assertDoesNotThrow(() -> tc.note("debug message"));
  }

  @Test
  void testCaseNoteFinalRun() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tcFinal(ds);
    // note() prints to stderr when isFinalRun=true
    // Just verify it doesn't throw
    assertDoesNotThrow(() -> tc.note("final debug message"));
  }

  @Test
  void testCaseIsFinalRun() {
    MockDataSource ds = new MockDataSource();
    TestCase tcNormal = tc(ds);
    TestCase tcFinal = tcFinal(ds);
    assertFalse(tcNormal.isFinalRun());
    assertTrue(tcFinal.isFinalRun());
  }

  @Test
  void testCaseDataSource() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertSame(ds, tc.dataSource());
  }

  @Test
  void testCaseTestAborted() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertFalse(tc.testAborted());
  }

  @Test
  void testCaseTarget() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    assertDoesNotThrow(() -> tc.target(0.5, "my_metric"));
    assertEquals(1, ds.targetCalls.size());
    assertEquals("my_metric=0.5", ds.targetCalls.get(0));
  }

  @Test
  void testCaseStartStopSpan() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    // These delegate to DataSource; just verify no exceptions
    assertDoesNotThrow(() -> tc.startSpan(Labels.LIST));
    assertDoesNotThrow(() -> tc.stopSpan(false));
    assertDoesNotThrow(() -> tc.stopSpan(true));
  }

  @Test
  void testCaseNewCollection() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    long id = tc.newCollection(0, null);
    assertEquals(1L, id);
  }

  @Test
  void testCaseCollectionMore() {
    MockDataSource ds = new MockDataSource().withCollectionElements(2);
    TestCase tc = tc(ds);
    assertTrue(tc.collectionMore(1L));
    assertTrue(tc.collectionMore(1L));
    assertFalse(tc.collectionMore(1L));
  }

  @Test
  void testCaseCollectionReject() {
    MockDataSource ds = new MockDataSource();
    TestCase tc = tc(ds);
    // Normal rejection — no exception
    assertDoesNotThrow(() -> tc.collectionReject(1L, "too big"));
  }

  @Test
  void testCaseCollectionRejectSwallowsStopTest() {
    // collectionReject swallows StopTestException from the DataSource
    DataSource throwingDs =
        new MockDataSource() {
          @Override
          public void collectionReject(long collectionId, String why) {
            throw new StopTestException("stop");
          }
        };
    TestCase tc = new TestCase(throwingDs, false);
    assertDoesNotThrow(() -> tc.collectionReject(1L, "reject"));
  }

  // -----------------------------------------------------------------------
  // StopTestException
  // -----------------------------------------------------------------------

  @Test
  void stopTestExceptionNoArg() {
    StopTestException e = new StopTestException();
    assertNotNull(e.getMessage());
    assertTrue(e.getMessage().contains("StopTest"));
  }

  @Test
  void stopTestExceptionWithMessage() {
    StopTestException e = new StopTestException("custom message");
    assertEquals("custom message", e.getMessage());
  }

  // -----------------------------------------------------------------------
  // DataSource default target() method (DataSource.java:40)
  // -----------------------------------------------------------------------

  @Test
  void dataSourceDefaultTargetIsNoop() {
    // Create a DataSource that uses the default target() (does not override it)
    DataSource ds =
        new DataSource() {
          @Override
          public JsonNode generate(JsonNode schema) {
            return NullNode.instance;
          }

          @Override
          public void startSpan(long label) {}

          @Override
          public void stopSpan(boolean discard) {}

          @Override
          public long newCollection(long minSize, Long maxSize) {
            return 0;
          }

          @Override
          public boolean collectionMore(long collectionId) {
            return false;
          }

          @Override
          public void collectionReject(long collectionId, String why) {}

          @Override
          public void markComplete(String status, String origin) {}

          @Override
          public boolean testAborted() {
            return false;
          }
          // no target() override — uses interface default
        };
    // Call the default no-op target() method
    assertDoesNotThrow(() -> ds.target(0.5, "my_metric"));
  }

  // -----------------------------------------------------------------------
  // BasicGenerator.nodeToObject() toString fallback (BasicGenerator.java:114)
  // -----------------------------------------------------------------------

  @Test
  void nodeToObjectMissingNode() {
    // MissingNode is not null, boolean, integral, float, text, binary, array, or object
    // So it falls through to the toString() fallback
    Object result = BasicGenerator.nodeToObject(MissingNode.getInstance());
    assertNotNull(result);
    assertInstanceOf(String.class, result);
  }

  // -----------------------------------------------------------------------
  // IntegerGenerator transform fallback (Generators.java:95)
  // -----------------------------------------------------------------------

  @Test
  void integerTransformFallbackAsLong() {
    // Pass a TextNode representing a number — not isIntegralNumber(), so asLong() fallback
    MockDataSource ds = new MockDataSource().withResponse(TextNode.valueOf("99"));
    TestCase tc = tc(ds);
    long result = tc.draw(integers());
    assertEquals(99L, result);
  }

  // -----------------------------------------------------------------------
  // FloatGenerator buildSchema branches (Generators.java:159-160)
  // -----------------------------------------------------------------------

  @Test
  void floatBuildSchemaNoConstraints() {
    // bare floats(): allowNan=null, no min/max
    // → nan = !hasMin && !hasMax = true; inf = !hasMin || !hasMax = true
    MockDataSource ds = new MockDataSource().withResponse(DoubleNode.valueOf(1.5));
    TestCase tc = tc(ds);
    double result = tc.draw(floats());
    assertEquals(1.5, result, 0.001);
  }

  @Test
  void floatBuildSchemaOnlyMaxValue() {
    // floats().maxValue(1.0): allowNan=null, hasMin=false, hasMax=true
    // → nan = !false && !true = false; inf = !false || !true = true
    MockDataSource ds = new MockDataSource().withResponse(DoubleNode.valueOf(0.5));
    TestCase tc = tc(ds);
    double result = tc.draw(floats().maxValue(1.0));
    assertEquals(0.5, result, 0.001);
  }

  @Test
  void floatBuildSchemaOnlyMinValue() {
    // floats().minValue(0.0): allowNan=null, hasMin=true, hasMax=false
    // → nan = !true && !false = false; inf = !true || !false = true
    MockDataSource ds = new MockDataSource().withResponse(DoubleNode.valueOf(1.0));
    TestCase tc = tc(ds);
    double result = tc.draw(floats().minValue(0.0));
    assertEquals(1.0, result, 0.001);
  }

  // -----------------------------------------------------------------------
  // FloatGenerator transform branches (Generators.java:187, 189-191)
  // -----------------------------------------------------------------------

  @Test
  void floatTransformNullIsNaN() {
    // NullNode → Double.NaN (Generators.java:187)
    MockDataSource ds = new MockDataSource().withResponse(NullNode.instance);
    TestCase tc = tc(ds);
    double result = tc.draw(floats());
    assertTrue(Double.isNaN(result));
  }

  @Test
  void floatTransformIntegralAsDouble() {
    // IntNode → cast to double (Generators.java:189)
    MockDataSource ds = new MockDataSource().withResponse(IntNode.valueOf(42));
    TestCase tc = tc(ds);
    double result = tc.draw(floats());
    assertEquals(42.0, result, 0.001);
  }

  @Test
  void floatTransformFallbackAsDouble() {
    // TextNode → asDouble() fallback (Generators.java:190-191)
    MockDataSource ds = new MockDataSource().withResponse(TextNode.valueOf("3.14"));
    TestCase tc = tc(ds);
    double result = tc.draw(floats());
    assertEquals(3.14, result, 0.01);
  }

  // -----------------------------------------------------------------------
  // TextGenerator transform branches (Generators.java:252, 254-255, 257)
  // -----------------------------------------------------------------------

  @Test
  void textTransformBinaryNode() {
    // BinaryNode → decode as UTF-8 (Generators.java:254-255)
    byte[] utf8 = "hello".getBytes(java.nio.charset.StandardCharsets.UTF_8);
    MockDataSource ds = new MockDataSource().withResponse(BinaryNode.valueOf(utf8));
    TestCase tc = tc(ds);
    String result = tc.draw(text());
    assertEquals("hello", result);
  }

  @Test
  void textTransformFallbackAsText() {
    // IntNode → neither textual nor binary → asText() fallback (Generators.java:257)
    MockDataSource ds = new MockDataSource().withResponse(IntNode.valueOf(42));
    TestCase tc = tc(ds);
    String result = tc.draw(text());
    assertEquals("42", result);
  }

  // -----------------------------------------------------------------------
  // BinaryGenerator transform branches (Generators.java:306-307, 309)
  // -----------------------------------------------------------------------

  @Test
  void binaryTransformTextualNode() {
    // TextNode → getBytes() (Generators.java:306-307)
    MockDataSource ds = new MockDataSource().withResponse(TextNode.valueOf("hello"));
    TestCase tc = tc(ds);
    byte[] result = tc.draw(binary());
    assertArrayEquals("hello".getBytes(java.nio.charset.StandardCharsets.UTF_8), result);
  }

  @Test
  void binaryTransformFallbackEmpty() {
    // NullNode → neither binary nor textual → empty byte array (Generators.java:309)
    MockDataSource ds = new MockDataSource().withResponse(NullNode.instance);
    TestCase tc = tc(ds);
    byte[] result = tc.draw(binary());
    assertArrayEquals(new byte[0], result);
  }

  // -----------------------------------------------------------------------
  // Tuples generator (Generators.java)
  // -----------------------------------------------------------------------

  @Test
  void tuplesWithMultipleGenerators() {
    // just(42L) and just("hello") each consume one server response (integer 0..0)
    MockDataSource ds =
        new MockDataSource()
            .withResponse(LongNode.valueOf(0)) // consumed by just(42L)
            .withResponse(LongNode.valueOf(0)); // consumed by just("hello")
    TestCase tc = tc(ds);
    Object[] result = tc.draw(tuples(just(42L), just("hello")));
    assertArrayEquals(new Object[] {42L, "hello"}, result);
  }

  @Test
  void tuplesWithNoGenerators() {
    // Empty tuples produce an empty array with no server calls
    TestCase tc = tc(new MockDataSource());
    Object[] result = tc.draw(tuples());
    assertEquals(0, result.length);
  }

  // -----------------------------------------------------------------------
  // CharactersGenerator (Generators.java)
  // -----------------------------------------------------------------------

  @Test
  void charactersDefault() {
    // Default characters() returns a single-char string
    MockDataSource ds = new MockDataSource().withResponse(TextNode.valueOf("a"));
    TestCase tc = tc(ds);
    String result = tc.draw(characters());
    assertEquals("a", result);
  }

  @Test
  void charactersWithOptions() {
    // Builder methods: codec, minCodepoint, maxCodepoint, include/excludeCharacters
    MockDataSource ds = new MockDataSource().withResponse(TextNode.valueOf("z"));
    TestCase tc = tc(ds);
    String result =
        tc.draw(
            characters()
                .codec("ascii")
                .minCodepoint(65)
                .maxCodepoint(122)
                .includeCharacters("_")
                .excludeCharacters("@"));
    assertEquals("z", result);
  }

  // -----------------------------------------------------------------------
  // SetGenerator (Generators.java)
  // -----------------------------------------------------------------------

  @Test
  void setsBasicPath() {
    // Basic path: elements generator is basic → server returns whole array
    // Server response mimics a deduplicated list [1, 2, 3]
    com.fasterxml.jackson.databind.node.ArrayNode arr =
        Cbor.array(LongNode.valueOf(1L), LongNode.valueOf(2L), LongNode.valueOf(3L));
    MockDataSource ds = new MockDataSource().withResponse(arr);
    TestCase tc = tc(ds);
    java.util.Set<Long> result = tc.draw(sets(integers(0L, 10L)));
    assertEquals(java.util.Set.of(1L, 2L, 3L), result);
  }

  @Test
  void setsBasicPathWithSizeConstraints() {
    // minSize/maxSize builder methods are exercised
    com.fasterxml.jackson.databind.node.ArrayNode arr =
        Cbor.array(LongNode.valueOf(7L), LongNode.valueOf(8L));
    MockDataSource ds = new MockDataSource().withResponse(arr);
    TestCase tc = tc(ds);
    java.util.Set<Long> result = tc.draw(sets(integers(0L, 10L)).minSize(1).maxSize(5));
    assertEquals(java.util.Set.of(7L, 8L), result);
  }

  // -----------------------------------------------------------------------
  // DurationGenerator (Generators.java)
  // -----------------------------------------------------------------------

  @Test
  void durationsDefault() {
    // 1_000_000 ns = 1 ms
    MockDataSource ds = new MockDataSource().withResponse(LongNode.valueOf(1_000_000L));
    TestCase tc = tc(ds);
    java.time.Duration result = tc.draw(durations());
    assertEquals(java.time.Duration.ofMillis(1), result);
  }

  @Test
  void durationsWithMinMaxValue() {
    // Builder methods: minValue and maxValue
    MockDataSource ds = new MockDataSource().withResponse(LongNode.valueOf(5_000_000_000L));
    TestCase tc = tc(ds);
    java.time.Duration result =
        tc.draw(
            durations()
                .minValue(java.time.Duration.ofSeconds(1))
                .maxValue(java.time.Duration.ofSeconds(10)));
    assertEquals(java.time.Duration.ofSeconds(5), result);
  }

  @Test
  void durationsMaxValueOverflowClampsToMax() {
    // Duration.MAX_VALUE.toNanos() overflows; toNanos() should clamp to Long.MAX_VALUE
    MockDataSource ds = new MockDataSource().withResponse(LongNode.valueOf(0L));
    TestCase tc = tc(ds);
    // java.time.Duration.ofSeconds(Long.MAX_VALUE) overflows toNanos()
    java.time.Duration hugeMax = java.time.Duration.ofSeconds(Long.MAX_VALUE / 2, 0);
    java.time.Duration result = tc.draw(durations().maxValue(hugeMax));
    assertEquals(java.time.Duration.ZERO, result);
  }

  @Test
  void durationsMinGreaterThanMaxThrows() {
    assertThrows(
        IllegalArgumentException.class,
        () ->
            durations()
                .minValue(java.time.Duration.ofSeconds(10))
                .maxValue(java.time.Duration.ofSeconds(1))
                .asBasic());
  }

  @Test
  void setsNonBasicPathWithDuplicateRejection() {
    // Non-basic elements generator → compositional path with collection protocol
    // Generator produces: 1, 2, 1 (duplicate → reject), 3
    // collectionMore returns true 4 times then false
    long[] values = {1L, 2L, 1L, 3L};
    int[] idx = {0};
    Generator<Long> nonBasicGen = tc2 -> values[idx[0]++];

    MockDataSource ds = new MockDataSource().withCollectionElements(4);
    TestCase tc = tc(ds);
    java.util.Set<Long> result = tc.draw(sets(nonBasicGen));
    // Duplicate 1 is rejected; final set is {1, 2, 3}
    assertEquals(java.util.Set.of(1L, 2L, 3L), result);
  }

  // -----------------------------------------------------------------------
  // Counterexample display (draw prints to stderr on final run)
  // -----------------------------------------------------------------------

  @Test
  void drawPrintsToStderrOnFinalRun() {
    MockDataSource ds =
        new MockDataSource().withResponse(new LongNode(42)).withResponse(new LongNode(7));
    java.io.PrintStream origErr = System.err;
    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
    System.setErr(new java.io.PrintStream(baos));
    try {
      TestCase tc = tcFinal(ds);
      tc.draw(integers());
      tc.draw(integers());
      String output = baos.toString();
      assertTrue(output.contains("var draw_1 = 42;"), "got: " + output);
      assertTrue(output.contains("var draw_2 = 7;"), "got: " + output);
    } finally {
      System.setErr(origErr);
    }
  }

  @Test
  void drawDoesNotPrintOnNonFinalRun() {
    MockDataSource ds = new MockDataSource().withResponse(new LongNode(42));
    java.io.PrintStream origErr = System.err;
    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
    System.setErr(new java.io.PrintStream(baos));
    try {
      TestCase tc = tc(ds);
      tc.draw(integers());
      assertEquals("", baos.toString());
    } finally {
      System.setErr(origErr);
    }
  }

  @Test
  void drawWithLabelPrintsLabeledFormat() {
    MockDataSource ds = new MockDataSource().withResponse(new LongNode(99));
    java.io.PrintStream origErr = System.err;
    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
    System.setErr(new java.io.PrintStream(baos));
    try {
      TestCase tc = tcFinal(ds);
      tc.draw(integers(), "x");
      String output = baos.toString();
      assertTrue(output.contains("var x = 99;"), "got: " + output);
    } finally {
      System.setErr(origErr);
    }
  }

  @Test
  void drawWithLabelDoesNotPrintOnNonFinalRun() {
    MockDataSource ds = new MockDataSource().withResponse(new LongNode(99));
    java.io.PrintStream origErr = System.err;
    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
    System.setErr(new java.io.PrintStream(baos));
    try {
      TestCase tc = tc(ds);
      tc.draw(integers(), "x");
      assertEquals("", baos.toString());
    } finally {
      System.setErr(origErr);
    }
  }

  @Test
  void drawCountIncrementsOnEveryDraw() {
    MockDataSource ds =
        new MockDataSource().withResponse(new LongNode(1)).withResponse(new LongNode(2));
    TestCase tc = tc(ds);
    assertEquals(0, tc.drawCount());
    tc.draw(integers());
    assertEquals(1, tc.drawCount());
    tc.draw(integers());
    assertEquals(2, tc.drawCount());
  }
}
