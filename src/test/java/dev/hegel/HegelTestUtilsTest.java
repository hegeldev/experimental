package dev.hegel;

import static dev.hegel.HegelTestUtils.*;
import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

/** Tests for HegelTestUtils: assertAllExamples, assertNoExamples, findAny, minimal. */
class HegelTestUtilsTest {

  // -----------------------------------------------------------------------
  // assertAllExamples
  // -----------------------------------------------------------------------

  @Test
  void assertAllExamplesPassesWhenAllSatisfy() {
    // All integers in [0, 10] are >= 0, so this should pass with no error
    assertAllExamples(integers(0, 10), x -> x >= 0);
  }

  @Test
  void assertAllExamplesThrowsWhenPredicateFails() {
    // No integer in [0, 10] is < 0, so predicate always fails → AssertionError
    assertThrows(AssertionError.class, () -> assertAllExamples(integers(0, 10), x -> x < 0));
  }

  // -----------------------------------------------------------------------
  // assertNoExamples
  // -----------------------------------------------------------------------

  @Test
  void assertNoExamplesPassesWhenNoneSatisfy() {
    // No integer in [0, 10] exceeds 100 → condition is never met → pass
    assertNoExamples(integers(0, 10), x -> x > 100);
  }

  @Test
  void assertNoExamplesThrowsWhenConditionMet() {
    // All integers in [0, 10] satisfy x >= 0 → condition always met → AssertionError
    assertThrows(AssertionError.class, () -> assertNoExamples(integers(0, 10), x -> x >= 0));
  }

  // -----------------------------------------------------------------------
  // findAny
  // -----------------------------------------------------------------------

  @Test
  void findAnyReturnsMatchingValue() {
    // The unbounded integer generator can produce positive values
    Long found = findAny(integers(), x -> x > 0L);
    assertNotNull(found);
    assertTrue(found > 0L, "Expected positive value but got: " + found);
  }

  @Test
  void findAnyThrowsWhenNoMatchPossible() {
    // integers(0, 0) always produces 0; 0 > 0 is false → no match → AssertionError
    assertThrows(AssertionError.class, () -> findAny(integers(0L, 0L), x -> x > 0L));
  }

  // -----------------------------------------------------------------------
  // minimal
  // -----------------------------------------------------------------------

  @Test
  void minimalReturnsMinimalValue() {
    // Shrinking should find that 100 is the smallest integer satisfying x >= 100
    Long min = minimal(integers(), x -> x >= 100L);
    assertEquals(100L, min, "Expected minimal value 100 but got: " + min);
  }

  @Test
  void minimalThrowsWhenNoMatchPossible() {
    // integers(0, 0) always produces 0; 0 > 0 is false → no match → AssertionError
    assertThrows(AssertionError.class, () -> minimal(integers(0L, 0L), x -> x > 0L));
  }
}
