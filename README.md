> **Beta notice:** hegel-java is in early development. Bugs and API changes are expected. Please report issues at https://github.com/hegeldev/hegel-java/issues.

> **Note:** This implementation was generated with the assistance of Claude (claude-sonnet-4-6) and has not been extensively used in production. Please report issues.

# Hegel for Java

**hegel-java** is a property-based testing library for Java, based on [Hypothesis](https://hypothesis.readthedocs.io/), using the [Hegel protocol](https://hegel.dev).

## Prerequisites

- Java 21+
- Maven 3.8+
- Python and [uv](https://docs.astral.sh/uv/) (for running hegel-core):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Installation

hegel-java is not yet published to Maven Central. Install it locally first:

```bash
git clone https://github.com/hegeldev/hegel-java.git
cd hegel-java
mvn install -DskipTests -q
```

Then add it to your `pom.xml`:

```xml
<dependency>
    <groupId>dev.hegel</groupId>
    <artifactId>hegel-java</artifactId>
    <version>0.1.0-SNAPSHOT</version>
    <scope>test</scope>
</dependency>
```

## Quick Start

Property-based testing generates many inputs automatically and shrinks failures to the simplest possible case. Here is a complete example that finds a bug in a sort function.

First, define a sort function with a subtle bug — it uses a `TreeSet`, which silently removes duplicate elements:

```java
import java.util.ArrayList;
import java.util.List;
import java.util.TreeSet;

/** A sort with a bug: TreeSet removes duplicate elements. */
static <T extends Comparable<T>> List<T> badSort(List<T> list) {
    return new ArrayList<>(new TreeSet<>(list));
}
```

Write a property test that checks that sorting preserves the element count:

```java
import dev.hegel.Hegel;
import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

@Test
void sortPreservesLength() {
    Hegel.test("sort preserves length", tc -> {
        List<Long> xs = tc.draw(lists(integers(-10, 10)));
        List<Long> sorted = badSort(xs);
        assertTrue(xs.size() == sorted.size(),
            "Sort must not lose elements: " + xs + " -> " + sorted);
    });
}
```

Run with Maven:

```bash
mvn test
```

Hegel finds the bug and shrinks the failing case to its minimal form:

```
AssertionError: Sort must not lose elements: [0, 0] -> [0]
```

Hegel generated 100 lists (the default). When it found a failing case like `[3, 3, 1, 2]`, it automatically shrunk that list until it found `[0, 0]` — the simplest possible list that exposes the duplicate-removal bug.

## Tutorial

### Your first passing test

The simplest property to test: a generated integer stays within its declared bounds.

```java
import dev.hegel.Hegel;
import static dev.hegel.generators.Generators.*;
import static org.junit.jupiter.api.Assertions.*;

@Test
void integersAreInRange() {
    Hegel.test("integers are in range", tc -> {
        long n = tc.draw(integers(0, 100));
        assertTrue(n >= 0 && n <= 100, "Expected n in [0,100], got " + n);
    });
}
```

Run `mvn test`. Hegel generates 100 values and the test passes.

### Your first failing test

Now write a property that looks right but is subtly wrong. Integer addition can overflow:

```java
@Test
void additionLooksPositive() {
    Hegel.test("sum of two positives is larger", tc -> {
        long x = tc.draw(integers(1, Long.MAX_VALUE));
        long y = tc.draw(integers(1, Long.MAX_VALUE));
        // x + y overflows when y = Long.MAX_VALUE
        assertTrue(x + y > x, x + " + " + y + " should grow");
    });
}
```

Hegel finds the bug and shrinks it to its simplest form:

```
AssertionError: 1 + 9223372036854775807 should grow
```

The shrunk example uses the smallest `x` (1) that exposes the overflow. Hegel found a large pair first, then shrunk until it found the minimal case.

### Constrained generation

If you only want even numbers, use `filter()`:

```java
Generator<Long> evens = integers(-100, 100).filter(n -> n % 2 == 0);
```

Or use `map()` to derive a value:

```java
Generator<Long> doubled = integers(0, 50).map(n -> n * 2);
```

### Dependent generation

Because drawing values is imperative, you can use an earlier result to configure a later generator. This is one of Hegel's most powerful features:

```java
@Test
void listIndexIsAlwaysValid() {
    Hegel.test("list index is always valid", tc -> {
        int n = (int) tc.draw(integers(1, 10));
        List<Long> lst = tc.draw(lists(integers()).minSize(n).maxSize(n));
        int index = (int) tc.draw(integers(0, n - 1));
        // lst always has exactly n elements, so index is always in bounds
        assertNotNull(lst.get(index));
    });
}
```

First draw the length `n`, then use it to generate a list of exactly that length, then draw a valid index. All three draws are correlated — and Hegel can still shrink the whole thing together.

### Composite objects

Draw multiple values and combine them into a domain object:

```java
record Point(long x, long y) {}

@Test
void pointsAreInQuadrant() {
    Hegel.test("points are in first quadrant", tc -> {
        long x = tc.draw(integers(0, 1000));
        long y = tc.draw(integers(0, 1000));
        Point p = new Point(x, y);
        assertTrue(p.x() >= 0 && p.y() >= 0);
    });
}
```

When a test fails, Hegel shrinks all the draws together, so the reported failing `Point` is always the simplest one.

### Debugging with `note()`

Use `tc.note()` to print values during the final shrunk replay:

```java
Hegel.test("note example", tc -> {
    long x = tc.draw(integers());
    tc.note("drew x = " + x);
    // ... rest of test
});
```

Notes are suppressed during normal runs and only printed when replaying the shrunk failure, so they do not slow down test execution.

### Changing the number of test cases

```java
Settings s = Settings.builder().testCases(500).build();
Hegel.test("more thorough test", s, tc -> {
    // ...
});
```

The default is 100. Increase for properties that need wider coverage; decrease if they are slow.

## API Reference

### Drawing values

Inside `Hegel.test()`, you receive a `TestCase` (`tc`) that you use to draw generated values:

```java
Hegel.test("my property", tc -> {
    long    n1 = tc.draw(integers());                        // any long
    long    n2 = tc.draw(integers(0, 100));                  // in [0, 100]
    int     n3 = tc.draw(integers(0, 100).asInt());          // as int
    double  d1 = tc.draw(floats());                          // any double (including NaN, ±∞)
    double  d2 = tc.draw(floats().minValue(0.0).maxValue(1.0));
    boolean b1 = tc.draw(booleans());
    String  s1 = tc.draw(text());
    String  s2 = tc.draw(text().minSize(3).maxSize(20).ascii());
    byte[]  b2 = tc.draw(binary().minSize(1).maxSize(256));
});
```

### Collection generators

```java
List<Long>        xs1 = tc.draw(lists(integers()));
List<Long>        xs2 = tc.draw(lists(integers(0, 10)).minSize(1).maxSize(5));
Set<Long>         s   = tc.draw(sets(integers(0, 100)));         // unique elements
Map<Long, String> m   = tc.draw(maps(integers(), text()));
Object[]          t   = tc.draw(tuples(integers(), text(), booleans())); // fixed-length tuple
Long              opt = tc.draw(optional(integers()));           // null or Long
Long              x1  = tc.draw(sampledFrom(1L, 2L, 3L));
Long              x2  = tc.draw(oneOf(integers(0, 5), integers(100, 200)));
```

### Format generators

```java
String            email = tc.draw(emails());
String            url   = tc.draw(urls());
String            ip4   = tc.draw(ipv4Addresses());
String            ip6   = tc.draw(ipv6Addresses());
String            date  = tc.draw(dates());           // ISO 8601, e.g. "2024-03-15"
String            time  = tc.draw(times());
String            dt    = tc.draw(datetimes());
String            s     = tc.draw(fromRegex("[a-z]{3,8}"));
String            c     = tc.draw(characters());      // single Unicode character
java.time.Duration d    = tc.draw(durations().maxValue(java.time.Duration.ofSeconds(60)));
```

### Combinators

```java
// map: transform a generated value (basic generators stay basic)
Generator<String> labeled = integers(0, 100).map(n -> "item-" + n);

// filter: constrain generated values (uses assume() under the hood)
Generator<Long> positive = integers(-100, 100).filter(n -> n > 0);

// flatMap: generate a value that depends on a previously drawn value
Generator<String> sameLength = integers(1, 10).flatMap(n ->
    text().minSize(n.intValue()).maxSize(n.intValue())
);
```

### Control functions

```java
tc.assume(x > 0);           // skip this test case if false
tc.note("x = " + x);       // print during the final shrunk replay
tc.target((double) x, "x"); // guide Hegel toward larger values of x
```

### Settings

```java
Settings s = Settings.builder()
    .testCases(500)                    // number of test cases (default: 100)
    .seed(42L)                         // deterministic seed
    .derandomize(true)                 // replay known examples only (auto-enabled in CI)
    .database("/tmp/mydb")             // example database path (null = default location)
    // .database("")                   // pass "" to disable the database entirely
    .suppressHealthCheck("too_slow")
    .build();

Hegel.test("my property", s, tc -> { ... });
```

### Builder form

When you need to set a `databaseKey` separately from the test name:

```java
new Hegel(tc -> {
    long x = tc.draw(integers());
    // ...
})
.settings(Settings.builder().testCases(200).build())
.databaseKey("my_property_v2")
.run();
```

## Test Utilities

`HegelTestUtils` provides helpers for asserting properties of generators themselves — useful when writing tests for code that uses Hegel:

```java
import dev.hegel.HegelTestUtils;
import static dev.hegel.generators.Generators.*;

// Assert every generated value satisfies a predicate
HegelTestUtils.assertAllExamples(integers(0, 100), n -> n >= 0 && n <= 100);

// Assert no generated value satisfies a predicate
HegelTestUtils.assertNoExamples(integers(0, 10), n -> n < 0);

// Find any value satisfying a predicate (returns it, or throws if none found)
long found = HegelTestUtils.findAny(integers(-100, 100), n -> n > 50);

// Find the minimal value satisfying a predicate (via shrinking)
long minimal = HegelTestUtils.minimal(integers(0, 1000), n -> n > 42);
// minimal == 43
```

## Development

```bash
just test        # run tests (no coverage enforcement)
just coverage    # run tests + enforce 100% line coverage
just check       # alias for coverage
just conformance # run conformance tests against hegel-core
```

## License

MIT — see [LICENSE](LICENSE).
