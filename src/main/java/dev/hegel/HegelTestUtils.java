package dev.hegel;

import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Predicate;

/**
 * Test utilities for verifying generator behavior in property-based tests.
 *
 * <p>These utilities use Hegel to test Hegel: they run property tests internally and provide
 * higher-level assertions about what generators can and cannot produce.
 *
 * <h2>Usage</h2>
 *
 * <pre>{@code
 * import static dev.hegel.HegelTestUtils.*;
 * import static dev.hegel.generators.Generators.*;
 *
 * // Every generated integer in [0, 100] must be non-negative
 * assertAllExamples(integers(0, 100), x -> x >= 0);
 *
 * // The unbounded integer generator can produce values greater than 1000
 * long large = findAny(integers(), x -> x > 1000);
 *
 * // The smallest integer satisfying x >= 100 is exactly 100
 * assertEquals(100L, minimal(integers(), x -> x >= 100));
 *
 * // No integer in [0, 100] exceeds 100
 * assertNoExamples(integers(0, 100), x -> x > 100);
 * }</pre>
 */
public final class HegelTestUtils {

  private HegelTestUtils() {}

  /**
   * Asserts that all generated values satisfy the predicate.
   *
   * <p>Runs a property test that draws from {@code gen} and checks {@code pred}. Throws {@link
   * AssertionError} (with the minimal failing value) if any value does not satisfy the predicate.
   */
  public static <T> void assertAllExamples(Generator<T> gen, Predicate<T> pred) {
    Hegel.test(
        "assertAllExamples",
        tc -> {
          T val = tc.draw(gen);
          if (!pred.test(val)) {
            throw new AssertionError("Generated value failed predicate: " + val);
          }
        });
  }

  /**
   * Asserts that no generated value satisfies the condition.
   *
   * <p>Throws {@link AssertionError} (with the minimal satisfying value) if any generated value
   * satisfies {@code cond}.
   */
  public static <T> void assertNoExamples(Generator<T> gen, Predicate<T> cond) {
    Hegel.test(
        "assertNoExamples",
        tc -> {
          T val = tc.draw(gen);
          if (cond.test(val)) {
            throw new AssertionError("Generated value satisfied forbidden condition: " + val);
          }
        });
  }

  /**
   * Finds any generated value satisfying the condition and returns it.
   *
   * <p>The returned value is the minimal (most-shrunk) example satisfying the condition. Throws
   * {@link AssertionError} if no matching value can be found.
   */
  public static <T> T findAny(Generator<T> gen, Predicate<T> cond) {
    AtomicReference<T> result = new AtomicReference<>();
    try {
      Hegel.test(
          "findAny",
          tc -> {
            T val = tc.draw(gen);
            if (cond.test(val)) {
              result.set(val);
              throw new AssertionError("found: " + val);
            }
          });
    } catch (AssertionError ignored) {
      // Expected: a matching value was found (test "fails" = findAny succeeds)
    }
    T found = result.get();
    if (found != null) {
      return found;
    }
    throw new AssertionError("findAny: no value satisfying condition was found");
  }

  /**
   * Finds the minimal (most-shrunk) generated value satisfying the condition.
   *
   * <p>Useful for verifying that Hegel's shrinking finds the true minimum. For example, {@code
   * minimal(integers(), x -> x >= 100)} should return exactly {@code 100L}.
   *
   * <p>Throws {@link AssertionError} if no matching value can be found.
   */
  public static <T> T minimal(Generator<T> gen, Predicate<T> cond) {
    AtomicReference<T> result = new AtomicReference<>();
    try {
      Hegel.test(
          "minimal",
          tc -> {
            T val = tc.draw(gen);
            if (cond.test(val)) {
              result.set(val);
              throw new AssertionError("found: " + val);
            }
          });
    } catch (AssertionError ignored) {
      // Expected: a matching value was found, shrunk to minimal
    }
    T found = result.get();
    if (found != null) {
      return found;
    }
    throw new AssertionError("minimal: no value satisfying condition was found");
  }
}
