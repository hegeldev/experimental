package dev.hegel;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;

/**
 * Marks a method as a Hegel property-based test.
 *
 * <p>The annotated method receives a {@link TestCase} parameter and is executed repeatedly by the
 * Hegel engine (default: 100 test cases). Failures are automatically shrunk to the minimal
 * counterexample.
 *
 * <pre>{@code
 * import static dev.hegel.generators.Generators.*;
 * import static org.junit.jupiter.api.Assertions.*;
 *
 * @HegelTest
 * void sortPreservesLength(TestCase tc) {
 *     List<Long> xs = tc.draw(lists(integers()));
 *     assertEquals(xs.size(), sort(xs).size());
 * }
 * }</pre>
 *
 * <p>Optional attributes control generation:
 *
 * <pre>{@code
 * @HegelTest(testCases = 500, seed = 42)
 * void myProperty(TestCase tc) { ... }
 * }</pre>
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Test
@ExtendWith(HegelExtension.class)
public @interface HegelTest {

  /** Number of test cases to run (default: 100). */
  int testCases() default 100;

  /**
   * Explicit random seed. Use {@link Long#MIN_VALUE} (the default) to let the engine choose a seed.
   */
  long seed() default Long.MIN_VALUE;

  /** If true, replay known failing examples only. Automatically enabled in CI. */
  boolean derandomize() default false;
}
