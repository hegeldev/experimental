package dev.hegel;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * A handle to the current test case.
 *
 * <p>Passed to {@code Hegel.test()} functions and provides methods for drawing values, making
 * assumptions, and recording notes.
 *
 * <h2>Example</h2>
 *
 * <pre>{@code
 * import static dev.hegel.Generators.*;
 *
 * Hegel.test("my property", tc -> {
 *     int x = tc.draw(integers());
 *     tc.assume(x > 0);
 *     tc.note("x = " + x);
 *     // ... assertions
 * });
 * }</pre>
 */
public class TestCase {

  private final DataSource dataSource;
  private final boolean isFinalRun;
  private int drawCount = 0;

  TestCase(DataSource dataSource, boolean isFinalRun) {
    this.dataSource = dataSource;
    this.isFinalRun = isFinalRun;
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /**
   * Draw a value from a generator.
   *
   * <p>During the final shrunk replay of a failing test, each draw is printed to stderr in
   * let-binding format: {@code var draw_1 = <value>;}
   *
   * @param generator the generator to draw from
   * @param <T> the type of value to draw
   * @return the generated value
   */
  public <T> T draw(Generator<T> generator) {
    T value = generator.generate(this);
    drawCount++;
    if (isFinalRun) {
      System.err.println("var draw_" + drawCount + " = " + value + ";");
    }
    return value;
  }

  /**
   * Draw a value from a generator with a descriptive label.
   *
   * <p>During the final shrunk replay, the draw is printed as {@code var label = <value>;} instead
   * of the default {@code var draw_N = <value>;}.
   *
   * @param generator the generator to draw from
   * @param label a variable name for this drawn value
   * @param <T> the type of value to draw
   * @return the generated value
   */
  public <T> T draw(Generator<T> generator, String label) {
    T value = generator.generate(this);
    drawCount++;
    if (isFinalRun) {
      System.err.println("var " + label + " = " + value + ";");
    }
    return value;
  }

  /**
   * Reject the current test case if {@code condition} is false.
   *
   * <p>This tells the engine that these particular inputs are not interesting, without counting
   * them as a test failure. The engine will try different inputs.
   */
  public void assume(boolean condition) {
    if (!condition) {
      throw new AssumeException();
    }
  }

  /**
   * Print a message, but only during the final (shrunk) replay of a failing test case. Use this for
   * debugging counterexamples.
   */
  public void note(String message) {
    if (isFinalRun) {
      System.err.println(message);
    }
  }

  /**
   * Guide the engine toward higher values of the given metric. The engine will try to maximize
   * {@code value}.
   *
   * @param value the metric value to optimize toward
   * @param label a descriptive label for this metric
   */
  public void target(double value, String label) {
    dataSource.target(value, label);
  }

  // -----------------------------------------------------------------------
  // Public helpers for generators
  // -----------------------------------------------------------------------

  /**
   * Send a CBOR schema and receive the raw generated value. Called by {@link
   * BasicGenerator#generate(TestCase)}.
   */
  public JsonNode generateRaw(JsonNode schema) {
    return dataSource.generate(schema);
  }

  /** Begin a span (called by non-basic generators). */
  public void startSpan(long label) {
    dataSource.startSpan(label);
  }

  /** End the current span. */
  public void stopSpan(boolean discard) {
    dataSource.stopSpan(discard);
  }

  /** Create a new server-managed collection for non-basic list generation. */
  public long newCollection(long minSize, Long maxSize) {
    return dataSource.newCollection(minSize, maxSize);
  }

  /** Ask the server whether to produce another element in the collection. */
  public boolean collectionMore(long collectionId) {
    return dataSource.collectionMore(collectionId);
  }

  /** Reject the last element drawn from a collection. */
  public void collectionReject(long collectionId, String why) {
    try {
      dataSource.collectionReject(collectionId, why);
    } catch (StopTestException e) {
      // ignore
    }
  }

  public DataSource dataSource() {
    return dataSource;
  }

  public boolean testAborted() {
    return dataSource.testAborted();
  }

  boolean isFinalRun() {
    return isFinalRun;
  }

  /** Return the number of top-level draws so far. */
  int drawCount() {
    return drawCount;
  }
}
