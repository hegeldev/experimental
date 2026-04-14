package dev.hegel;

import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * Integration tests targeting uncovered code paths. All tests use the real hegel-core server.
 * Exercises format generators, combinators, non-basic generator paths, error injection, and various
 * Settings configurations.
 */
class CoverageIntegrationTest {

  // -----------------------------------------------------------------------
  // Binary generator
  // -----------------------------------------------------------------------

  @Test
  void binaryGeneratesBytes() {
    Hegel.test(
        "binary generates bytes",
        tc -> {
          byte[] b = tc.draw(binary());
          assertNotNull(b);
        });
  }

  @Test
  void binaryWithSizeConstraints() {
    Hegel.test(
        "binary with size constraints",
        tc -> {
          byte[] b = tc.draw(binary().minSize(1).maxSize(8));
          assertTrue(b.length >= 1 && b.length <= 8);
        });
  }

  // -----------------------------------------------------------------------
  // just() generator
  // -----------------------------------------------------------------------

  @Test
  void justAlwaysReturnsConstant() {
    Hegel.test(
        "just always returns constant",
        tc -> {
          String s = tc.draw(just("hello"));
          assertEquals("hello", s);
        });
  }

  @Test
  void justWithNullValue() {
    Hegel.test(
        "just with null",
        tc -> {
          Object obj = tc.draw(just(null));
          assertNull(obj);
        });
  }

  // -----------------------------------------------------------------------
  // text() constraints
  // -----------------------------------------------------------------------

  @Test
  void textWithMinSize() {
    Hegel.test(
        "text with min size",
        tc -> {
          String s = tc.draw(text().minSize(3));
          assertTrue(s.length() >= 3);
        });
  }

  @Test
  void textWithMaxSize() {
    Hegel.test(
        "text with max size",
        tc -> {
          String s = tc.draw(text().maxSize(5));
          // maxSize is in codepoints, not Java chars (supplementary chars use 2 chars)
          assertTrue(s.codePointCount(0, s.length()) <= 5);
        });
  }

  @Test
  void textAscii() {
    Hegel.test(
        "text ascii only",
        tc -> {
          String s = tc.draw(text().ascii());
          for (char c : s.toCharArray()) {
            assertTrue(c < 128, "Expected ASCII char, got: " + (int) c);
          }
        });
  }

  @Test
  void textWithCodec() {
    Hegel.test(
        "text with explicit codec",
        tc -> {
          String s = tc.draw(text().codec("ascii"));
          for (char c : s.toCharArray()) {
            assertTrue(c < 128);
          }
        });
  }

  // -----------------------------------------------------------------------
  // integers() convenience
  // -----------------------------------------------------------------------

  @Test
  void integersTwoArgConvenience() {
    Hegel.test(
        "integers(min, max)",
        tc -> {
          long x = tc.draw(integers(0L, 10L));
          assertTrue(x >= 0 && x <= 10);
        });
  }

  @Test
  void integersOnlyMinSet() {
    Hegel.test(
        "integers with only min",
        tc -> {
          long x = tc.draw(integers().minValue(0));
          assertTrue(x >= 0);
        });
  }

  @Test
  void integersOnlyMaxSet() {
    Hegel.test(
        "integers with only max",
        tc -> {
          long x = tc.draw(integers().maxValue(0));
          assertTrue(x <= 0);
        });
  }

  @Test
  void integersAsInt() {
    Hegel.test(
        "integers as int",
        tc -> {
          int x = tc.draw(integers(-100, 100).asInt());
          assertTrue(x >= -100 && x <= 100);
        });
  }

  @Test
  void integersMinValueGreaterThanMaxThrows() {
    assertThrows(
        IllegalArgumentException.class,
        () -> integers().minValue(10).maxValue(5).generate(new TestCase(null, false)));
  }

  // -----------------------------------------------------------------------
  // floats() constraints
  // -----------------------------------------------------------------------

  @Test
  void floatsAllowNanExplicit() {
    Hegel.test(
        "floats with allowNan true",
        Settings.builder().testCases(50).build(),
        tc -> {
          double d = tc.draw(floats().allowNan(true).allowInfinity(false));
          assertTrue(!Double.isInfinite(d)); // no infinity
        });
  }

  @Test
  void floatsAllowInfinityExplicit() {
    Hegel.test(
        "floats with allowInfinity true",
        Settings.builder().testCases(50).build(),
        tc -> {
          double d = tc.draw(floats().allowInfinity(true).allowNan(false));
          assertFalse(Double.isNaN(d));
        });
  }

  @Test
  void floatsExcludeMinMax() {
    Hegel.test(
        "floats excludeMin excludeMax",
        tc -> {
          double d =
              tc.draw(floats().minValue(0.0).maxValue(1.0).excludeMin(true).excludeMax(true));
          assertTrue(d > 0.0 && d < 1.0);
        });
  }

  // -----------------------------------------------------------------------
  // filter() combinator
  // -----------------------------------------------------------------------

  @Test
  void filterCombinator() {
    Hegel.test(
        "filter combinator",
        tc -> {
          long x = tc.draw(integers(-100, 100).filter(n -> n > 0));
          assertTrue(x > 0);
        });
  }

  // -----------------------------------------------------------------------
  // flatMap() combinator
  // -----------------------------------------------------------------------

  @Test
  void flatMapCombinator() {
    Hegel.test(
        "flatMap combinator",
        tc -> {
          // flatMap: outer generates integer n, inner generates text of exactly n codepoints
          String s =
              tc.draw(
                  integers(1L, 5L)
                      .flatMap(n -> text().minSize(n.intValue()).maxSize(n.intValue())));
          // Size is in codepoints; verify via codePointCount (1-5)
          int cpCount = s.codePointCount(0, s.length());
          assertTrue(
              cpCount >= 1 && cpCount <= 5,
              "Expected 1-5 codepoints but got " + cpCount + " in: " + s);
        });
  }

  // -----------------------------------------------------------------------
  // map() on non-basic generator
  // -----------------------------------------------------------------------

  @Test
  void mapOnNonBasicGenerator() {
    Hegel.test(
        "map on non-basic generator",
        tc -> {
          // filter returns a non-basic generator; map on it should work
          String s = tc.draw(integers(1, 10).filter(n -> n > 0).map(n -> "n=" + n));
          assertTrue(s.startsWith("n="));
        });
  }

  // -----------------------------------------------------------------------
  // oneOf() — all paths
  // -----------------------------------------------------------------------

  @Test
  void oneOfSingleGenerator() {
    // oneOf with 1 generator returns the generator itself
    Generator<Long> single = oneOf(integers(5, 5));
    Hegel.test(
        "oneOf single",
        tc -> {
          long x = tc.draw(single);
          assertEquals(5L, x);
        });
  }

  @Test
  void oneOfAllBasicGenerators() {
    // oneOf with all basic generators (tagged tuple path)
    Hegel.test(
        "oneOf all basic",
        tc -> {
          long x = tc.draw(oneOf(integers(1, 3), integers(7, 9)));
          assertTrue((x >= 1 && x <= 3) || (x >= 7 && x <= 9));
        });
  }

  @Test
  void oneOfWithNonBasicGenerator() {
    // oneOf with a non-basic generator (index path)
    Generator<Long> nonBasic = integers(0, 100).filter(n -> n >= 0); // filter = non-basic
    Hegel.test(
        "oneOf with non-basic",
        tc -> {
          long x = tc.draw(oneOf(integers(200, 300), nonBasic));
          // Should be either 200-300 or 0-100
          assertTrue((x >= 200 && x <= 300) || (x >= 0 && x <= 100));
        });
  }

  @Test
  void oneOfEmptyThrows() {
    assertThrows(IllegalArgumentException.class, () -> oneOf(List.of()));
  }

  // -----------------------------------------------------------------------
  // optional() generator
  // -----------------------------------------------------------------------

  @Test
  void optionalGenerator() {
    Hegel.test(
        "optional generator",
        Settings.builder().testCases(50).build(),
        tc -> {
          Long val = tc.draw(optional(integers(1, 100)));
          // val is either null or between 1-100
          if (val != null) {
            assertTrue(val >= 1 && val <= 100);
          }
        });
  }

  // -----------------------------------------------------------------------
  // sampledFrom(List<T>) overload
  // -----------------------------------------------------------------------

  @Test
  void sampledFromList() {
    List<String> options = List.of("alpha", "beta", "gamma");
    Hegel.test(
        "sampledFrom list",
        tc -> {
          String s = tc.draw(sampledFrom(options));
          assertTrue(options.contains(s));
        });
  }

  @Test
  void sampledFromEmptyThrows() {
    assertThrows(IllegalArgumentException.class, () -> sampledFrom(List.of()));
  }

  // -----------------------------------------------------------------------
  // lists() non-basic path (filter element generator)
  // -----------------------------------------------------------------------

  @Test
  void listsWithNonBasicElements() {
    // filter() returns non-basic — list must use collection protocol
    Hegel.test(
        "lists non-basic elements",
        tc -> {
          List<Long> xs = tc.draw(lists(integers(0, 100).filter(n -> n >= 0)));
          for (long x : xs) {
            assertTrue(x >= 0 && x <= 100);
          }
        });
  }

  @Test
  void listsNonBasicWithSizeConstraints() {
    Hegel.test(
        "lists non-basic with size",
        tc -> {
          List<Long> xs = tc.draw(lists(integers(0, 10).filter(n -> n >= 0)).minSize(1).maxSize(5));
          assertTrue(xs.size() >= 1 && xs.size() <= 5);
        });
  }

  // -----------------------------------------------------------------------
  // sets() basic and non-basic paths
  // -----------------------------------------------------------------------

  @Test
  void setsBasicPath() {
    // Basic elements → server enforces uniqueness via "unique": true schema
    Hegel.test(
        "sets basic",
        Settings.builder().testCases(20).build(),
        tc -> {
          java.util.Set<Long> s = tc.draw(sets(integers(0, 10)));
          // All elements must be unique (basic path relies on server)
          for (Long v : s) {
            assertTrue(v >= 0 && v <= 10);
          }
        });
  }

  @Test
  void setsNonBasicPath() {
    // Non-basic elements → compositional path with client-side duplicate rejection
    Hegel.test(
        "sets non-basic",
        Settings.builder().testCases(20).build(),
        tc -> {
          java.util.Set<Long> s = tc.draw(sets(integers(0, 5).filter(n -> n >= 0)));
          for (Long v : s) {
            assertTrue(v >= 0 && v <= 5);
          }
          // All elements must be unique
          assertEquals(s.size(), new java.util.LinkedHashSet<>(s).size());
        });
  }

  // -----------------------------------------------------------------------
  // maps() non-basic path
  // -----------------------------------------------------------------------

  @Test
  void mapsWithNonBasicValues() {
    // filter() on values makes maps use the compositional path
    Hegel.test(
        "maps non-basic values",
        tc -> {
          Map<Long, Long> m = tc.draw(maps(integers(0, 10), integers(0, 100).filter(v -> v >= 0)));
          for (Map.Entry<Long, Long> e : m.entrySet()) {
            assertTrue(e.getKey() >= 0 && e.getKey() <= 10);
            assertTrue(e.getValue() >= 0 && e.getValue() <= 100);
          }
        });
  }

  @Test
  void mapsWithSizeConstraints() {
    Hegel.test(
        "maps with size constraints",
        tc -> {
          Map<Long, Long> m =
              tc.draw(maps(integers(0, 100), integers(0, 100)).minSize(1).maxSize(3));
          assertTrue(m.size() >= 1 && m.size() <= 3);
        });
  }

  // -----------------------------------------------------------------------
  // Format generators
  // -----------------------------------------------------------------------

  @Test
  void emailsGenerator() {
    Hegel.test(
        "emails",
        Settings.builder().testCases(20).build(),
        tc -> {
          String email = tc.draw(emails());
          assertTrue(email.contains("@"), "Expected email to contain @: " + email);
        });
  }

  @Test
  void urlsGenerator() {
    Hegel.test(
        "urls",
        Settings.builder().testCases(20).build(),
        tc -> {
          String url = tc.draw(urls());
          assertNotNull(url);
          assertFalse(url.isEmpty());
        });
  }

  @Test
  void domainsGenerator() {
    Hegel.test(
        "domains",
        Settings.builder().testCases(20).build(),
        tc -> {
          String domain = tc.draw(domains());
          assertNotNull(domain);
          assertFalse(domain.isEmpty());
        });
  }

  @Test
  void ipv4AddressesGenerator() {
    Hegel.test(
        "ipv4",
        Settings.builder().testCases(20).build(),
        tc -> {
          String ip = tc.draw(ipv4Addresses());
          assertTrue(ip.contains("."), "Expected dotted IPv4: " + ip);
        });
  }

  @Test
  void ipv6AddressesGenerator() {
    Hegel.test(
        "ipv6",
        Settings.builder().testCases(20).build(),
        tc -> {
          String ip = tc.draw(ipv6Addresses());
          assertNotNull(ip);
        });
  }

  @Test
  void ipAddressesGenerator() {
    Hegel.test(
        "ip addresses",
        Settings.builder().testCases(20).build(),
        tc -> {
          String ip = tc.draw(ipAddresses());
          assertNotNull(ip);
        });
  }

  @Test
  void datesGenerator() {
    Hegel.test(
        "dates",
        Settings.builder().testCases(20).build(),
        tc -> {
          String date = tc.draw(dates());
          assertNotNull(date);
          assertFalse(date.isEmpty());
        });
  }

  @Test
  void timesGenerator() {
    Hegel.test(
        "times",
        Settings.builder().testCases(20).build(),
        tc -> {
          String time = tc.draw(times());
          assertNotNull(time);
        });
  }

  @Test
  void datetimesGenerator() {
    Hegel.test(
        "datetimes",
        Settings.builder().testCases(20).build(),
        tc -> {
          String dt = tc.draw(datetimes());
          assertNotNull(dt);
        });
  }

  @Test
  void fromRegexGenerator() {
    Hegel.test(
        "fromRegex",
        Settings.builder().testCases(20).build(),
        tc -> {
          String s = tc.draw(fromRegex("[a-z]{3}"));
          // Without fullmatch the server may generate strings containing the pattern
          assertNotNull(s);
          assertFalse(s.isEmpty());
        });
  }

  @Test
  void fromRegexFullmatch() {
    Hegel.test(
        "fromRegex fullmatch",
        Settings.builder().testCases(20).build(),
        tc -> {
          String s = tc.draw(fromRegex("[a-z]{3}", true));
          assertTrue(s.matches("[a-z]{3}"), "Expected 3 lowercase letters: " + s);
        });
  }

  @Test
  void charactersGenerator() {
    Hegel.test(
        "characters",
        Settings.builder().testCases(20).build(),
        tc -> {
          String c = tc.draw(characters());
          assertEquals(1, c.codePointCount(0, c.length()), "Expected single codepoint: " + c);
        });
  }

  @Test
  void durationsGenerator() {
    Hegel.test(
        "durations",
        Settings.builder().testCases(20).build(),
        tc -> {
          java.time.Duration d =
              tc.draw(
                  durations()
                      .minValue(java.time.Duration.ZERO)
                      .maxValue(java.time.Duration.ofSeconds(60)));
          assertFalse(d.isNegative());
          assertTrue(d.compareTo(java.time.Duration.ofSeconds(60)) <= 0);
        });
  }

  // -----------------------------------------------------------------------
  // Settings configurations
  // -----------------------------------------------------------------------

  @Test
  void settingsWithSeed() {
    // Running with a seed should be deterministic
    Hegel.test(
        "with seed",
        Settings.builder().testCases(10).seed(42L).build(),
        tc -> {
          long x = tc.draw(integers());
          // Just verify we get values without error
        });
  }

  @Test
  void settingsWithDatabaseDisabled() {
    Hegel.test(
        "database disabled",
        Settings.builder().testCases(10).database("").build(),
        tc -> {
          long x = tc.draw(integers(0, 100));
          assertTrue(x >= 0 && x <= 100);
        });
  }

  @Test
  void settingsWithDerandomize() {
    Hegel.test(
        "derandomize",
        Settings.builder().testCases(10).derandomize(true).build(),
        tc -> {
          long x = tc.draw(integers());
        });
  }

  @Test
  void settingsWithSuppressHealthCheck() {
    Hegel.test(
        "suppress health check",
        Settings.builder().testCases(10).suppressHealthCheck("too_slow").build(),
        tc -> {
          long x = tc.draw(integers());
        });
  }

  // -----------------------------------------------------------------------
  // TestCase.note() with isFinalRun=true (via failing test replay)
  // -----------------------------------------------------------------------

  @Test
  void noteIsCalledDuringInterestingReplay() {
    // note() should print to stderr during the interesting (final) replay
    // We trigger a failure so the replay happens with isFinalRun=true
    assertThrows(
        AssertionError.class,
        () ->
            Hegel.test(
                "note in final replay",
                Settings.builder().testCases(100).build(),
                tc -> {
                  long x = tc.draw(integers(0, 3));
                  tc.note("Debugging x = " + x);
                  assertTrue(x < 3, "Expected x < 3, got " + x);
                }));
  }

  // -----------------------------------------------------------------------
  // TestCase.target()
  // -----------------------------------------------------------------------

  @Test
  void targetDoesNotBreakTest() {
    Hegel.test(
        "target hint",
        Settings.builder().testCases(20).build(),
        tc -> {
          long x = tc.draw(integers(0, 100));
          tc.target((double) x, "x_value");
        });
  }

  // -----------------------------------------------------------------------
  // Hegel.run() error paths
  // -----------------------------------------------------------------------

  @Test
  void hegelBuilderDatabaseKey() {
    // Test the Hegel builder methods directly
    new Hegel(tc -> {})
        .databaseKey("custom_key")
        .settings(Settings.builder().testCases(5).build())
        .run();
  }
}
