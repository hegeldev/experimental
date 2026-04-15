package dev.hegel;

import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.Method;
import java.util.List;

/** Tests for the {@link HegelTest} annotation and {@link HegelExtension}. */
class HegelTestAnnotationTest {

  // -----------------------------------------------------------------------
  // Basic @HegelTest usage
  // -----------------------------------------------------------------------

  @HegelTest
  void integersAreInRange(TestCase tc) {
    long n = tc.draw(integers(0, 100));
    assertTrue(n >= 0 && n <= 100, "Expected n in [0,100], got " + n);
  }

  @HegelTest
  void listsGenerateCorrectly(TestCase tc) {
    List<Long> xs = tc.draw(lists(integers(0, 10)).minSize(1).maxSize(5));
    assertFalse(xs.isEmpty());
    assertTrue(xs.size() <= 5);
    for (long x : xs) {
      assertTrue(x >= 0 && x <= 10);
    }
  }

  // -----------------------------------------------------------------------
  // @HegelTest with custom settings
  // -----------------------------------------------------------------------

  @HegelTest(testCases = 50)
  void customTestCaseCount(TestCase tc) {
    tc.draw(booleans());
  }

  @HegelTest(seed = 42)
  void explicitSeed(TestCase tc) {
    long n = tc.draw(integers());
    // Deterministic: same seed always produces the same sequence
    assertNotNull(n);
  }

  @HegelTest(testCases = 10, derandomize = true)
  void derandomizedTest(TestCase tc) {
    tc.draw(integers(0, 100));
  }

  // -----------------------------------------------------------------------
  // @HegelTest without TestCase parameter
  // -----------------------------------------------------------------------

  @HegelTest(testCases = 5)
  void noParameterTest() {
    // A @HegelTest with no TestCase parameter just runs the body multiple times
    assertTrue(true);
  }

  // -----------------------------------------------------------------------
  // @HegelTest catches failures and reports counterexamples
  // -----------------------------------------------------------------------

  @org.junit.jupiter.api.Test
  void hegelTestCatchesFailure() {
    AssertionError err =
        assertThrows(
            AssertionError.class,
            () -> {
              Hegel.test(
                  "always fails",
                  Settings.builder().testCases(1).build(),
                  tc -> {
                    fail("intentional failure");
                  });
            });
    assertNotNull(err);
  }

  // -----------------------------------------------------------------------
  // HegelExtension.invokeTestMethod error path tests
  // -----------------------------------------------------------------------

  /** Helper method that throws an Error (used by reflection in tests below). */
  @SuppressWarnings("unused")
  static void throwsError(TestCase tc) {
    throw new AssertionError("test error");
  }

  /** Helper method that throws a RuntimeException. */
  @SuppressWarnings("unused")
  static void throwsRuntime(TestCase tc) {
    throw new IllegalArgumentException("test runtime");
  }

  /** Helper method that throws a checked exception. */
  @SuppressWarnings("unused")
  static void throwsChecked(TestCase tc) throws Exception {
    throw new java.io.IOException("test checked");
  }

  @org.junit.jupiter.api.Test
  void invokeTestMethodRethrowsError() throws Exception {
    Method m = HegelTestAnnotationTest.class.getDeclaredMethod("throwsError", TestCase.class);
    m.setAccessible(true);
    AssertionError err =
        assertThrows(
            AssertionError.class, () -> HegelExtension.invokeTestMethod(m, null, null, true));
    assertEquals("test error", err.getMessage());
  }

  @org.junit.jupiter.api.Test
  void invokeTestMethodRethrowsRuntimeException() throws Exception {
    Method m = HegelTestAnnotationTest.class.getDeclaredMethod("throwsRuntime", TestCase.class);
    m.setAccessible(true);
    IllegalArgumentException err =
        assertThrows(
            IllegalArgumentException.class,
            () -> HegelExtension.invokeTestMethod(m, null, null, true));
    assertEquals("test runtime", err.getMessage());
  }

  @org.junit.jupiter.api.Test
  void invokeTestMethodWrapsCheckedException() throws Exception {
    Method m = HegelTestAnnotationTest.class.getDeclaredMethod("throwsChecked", TestCase.class);
    m.setAccessible(true);
    RuntimeException err =
        assertThrows(
            RuntimeException.class, () -> HegelExtension.invokeTestMethod(m, null, null, true));
    assertInstanceOf(java.io.IOException.class, err.getCause());
    assertEquals("test checked", err.getCause().getMessage());
  }

  @org.junit.jupiter.api.Test
  void invokeTestMethodIllegalAccessWrapsException() throws Exception {
    // Get a private method from another class to trigger IllegalAccessException
    Method m = Hegel.class.getDeclaredMethod("toAssertionError", Throwable.class);
    // Do NOT setAccessible — private method in another class triggers IllegalAccessException
    RuntimeException err =
        assertThrows(
            RuntimeException.class, () -> HegelExtension.invokeTestMethod(m, null, null, false));
    assertInstanceOf(IllegalAccessException.class, err.getCause());
  }
}
