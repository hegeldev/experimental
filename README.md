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
        assertEquals(xs.size(), sorted.size(),
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

Hegel generated hundreds of lists. When it found `[3, 3, 1, 2]` failing, it automatically shrunk that list until it found `[0, 0]` — the simplest possible list that exposes the duplicate-removal bug.

## Getting Started

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
Map<Long, String> m   = tc.draw(maps(integers(), text()));
Long              opt = tc.draw(optional(integers()));           // null or Long
Long              x1  = tc.draw(sampledFrom(1L, 2L, 3L));
Long              x2  = tc.draw(oneOf(integers(0, 5), integers(100, 200)));
```

### Format generators

```java
String email = tc.draw(emails());
String url   = tc.draw(urls());
String ip4   = tc.draw(ipv4Addresses());
String ip6   = tc.draw(ipv6Addresses());
String date  = tc.draw(dates());
String time  = tc.draw(times());
String dt    = tc.draw(datetimes());
String s     = tc.draw(fromRegex("[a-z]{3,8}"));
```

### Combinators

```java
// map: transform a generated value (basic generators stay basic)
Generator<String> gen = integers(0, 100).map(n -> "item-" + n);

// filter: constrain generated values (uses assume() under the hood)
Generator<Long> pos = integers(-100, 100).filter(n -> n > 0);

// flatMap: generate a value that depends on a previously drawn value
Generator<String> gen = integers(1, 10).flatMap(n ->
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
    .testCases(500)               // number of test cases (default: 100)
    .seed(42L)                    // deterministic seed
    .derandomize(true)            // replay known examples only (auto-enabled in CI)
    .database("/tmp/mydb")        // example database path
    .database("")                 // "" to disable the database
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

## Development

```bash
just test        # run tests (no coverage enforcement)
just coverage    # run tests + enforce 100% line coverage
just check       # alias for coverage
just conformance # run conformance tests against hegel-core
```

## License

MIT — see [LICENSE](LICENSE).
