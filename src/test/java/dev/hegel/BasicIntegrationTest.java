package dev.hegel;

import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * Basic integration tests that verify the core Hegel functionality by running actual property tests
 * against the hegel-core server.
 */
class BasicIntegrationTest {

  @Test
  void integersAreIntegers() {
    Hegel.test(
        "integers are integers",
        tc -> {
          long x = tc.draw(integers());
          // Just verify we got a value (no assertion failure = pass)
        });
  }

  @Test
  void booleansAreBoolean() {
    Hegel.test(
        "booleans are boolean",
        tc -> {
          boolean b = tc.draw(booleans());
          assertTrue(b || !b); // always true
        });
  }

  @Test
  void textIsString() {
    Hegel.test(
        "text is string",
        tc -> {
          String s = tc.draw(text());
          assertNotNull(s);
        });
  }

  @Test
  void listsHaveCorrectSize() {
    Hegel.test(
        "lists have correct size",
        tc -> {
          List<Long> xs = tc.draw(lists(integers()).minSize(2).maxSize(10));
          assertTrue(xs.size() >= 2 && xs.size() <= 10);
        });
  }

  @Test
  void assumeFiltersTestCases() {
    Hegel.test(
        "assume filters test cases",
        tc -> {
          long x = tc.draw(integers(-100, 100));
          tc.assume(x > 0);
          assertTrue(x > 0);
        });
  }

  @Test
  void reverseReverseIsIdentity() {
    Hegel.test(
        "reverse of reverse is identity",
        Settings.builder().testCases(50).build(),
        tc -> {
          List<Long> xs = tc.draw(lists(integers()));
          List<Long> reversed = reverse(xs);
          List<Long> doubleReversed = reverse(reversed);
          assertEquals(xs, doubleReversed);
        });
  }

  @Test
  void propertyTestCatchesBug() {
    // This test verifies that Hegel actually catches a bug and throws AssertionError.
    // buggySorted uses a TreeSet which loses duplicates; checking size preserves property.
    assertThrows(
        AssertionError.class,
        () ->
            Hegel.test(
                "buggy sort",
                Settings.builder().testCases(200).build(),
                tc -> {
                  List<Long> xs = tc.draw(lists(integers(-5, 5)).minSize(1));
                  List<Long> sorted = buggySorted(xs);
                  // A correct sort preserves element count (duplicates included)
                  assertEquals(
                      xs.size(),
                      sorted.size(),
                      "Sort must not lose elements, but got " + xs + " -> " + sorted);
                }));
  }

  @Test
  void sampledFromPicks() {
    Hegel.test(
        "sampledFrom picks from list",
        tc -> {
          String picked = tc.draw(sampledFrom("a", "b", "c"));
          assertTrue(picked.equals("a") || picked.equals("b") || picked.equals("c"));
        });
  }

  @Test
  void mapsHaveCorrectKeys() {
    Hegel.test(
        "maps have correct key types",
        tc -> {
          Map<Long, String> m = tc.draw(maps(integers(0, 100), text().maxSize(10)));
          for (Map.Entry<Long, String> e : m.entrySet()) {
            assertTrue(e.getKey() >= 0 && e.getKey() <= 100);
            assertNotNull(e.getValue());
          }
        });
  }

  @Test
  void floatsAreFiniteWhenBounded() {
    Hegel.test(
        "floats with bounds are finite",
        tc -> {
          double x = tc.draw(floats().minValue(0.0).maxValue(1.0));
          assertTrue(x >= 0.0 && x <= 1.0);
        });
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  private static <T> List<T> reverse(List<T> list) {
    java.util.ArrayList<T> result = new java.util.ArrayList<>(list);
    java.util.Collections.reverse(result);
    return result;
  }

  /** A deliberately buggy sort that doesn't handle duplicates correctly. */
  private static List<Long> buggySorted(List<Long> xs) {
    // This sort has a bug: it loses duplicates
    java.util.TreeSet<Long> set = new java.util.TreeSet<>(xs);
    return new java.util.ArrayList<>(set);
  }
}
