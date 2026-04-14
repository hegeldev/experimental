# hegel-java

A Java implementation of [Hegel](https://github.com/hegeldev/hegel-core), a property-based testing library backed by [Hypothesis](https://hypothesis.readthedocs.io/).

> **Note**: This library was authored with the assistance of Claude (claude-sonnet-4-6).

## Overview

Hegel runs property-based tests by communicating with a `hegel-core` subprocess over stdio using a CBOR binary protocol. The server manages test case generation, shrinking, and the test database.

## Prerequisites

- Java 21+
- Maven 3.8+
- [uv](https://docs.astral.sh/uv/) (for running hegel-core): `curl -LsSf https://astral.sh/uv/install.sh | sh`

## Quick Start

Add the dependency to your `pom.xml`:

```xml
<dependency>
    <groupId>dev.hegel</groupId>
    <artifactId>hegel-java</artifactId>
    <version>0.1.0-SNAPSHOT</version>
    <scope>test</scope>
</dependency>
```

Write a property test:

```java
import static dev.hegel.generators.Generators.*;
import dev.hegel.Hegel;

class SortTest {
    @Test
    void sortPreservesLength() {
        Hegel.test("sort preserves length", tc -> {
            List<Long> xs = tc.draw(lists(integers(-100, 100)));
            List<Long> sorted = sort(xs);
            assertEquals(xs.size(), sorted.size());
        });
    }
}
```

Run with Maven:

```
mvn test
```

Hegel catches the bug and shows the minimal failing case:

```
AssertionError: Counterexample found.
  Failing input: [0, 0]  (after shrinking from a larger list)
```

## API

### Entry Points

```java
// Simple form
Hegel.test("description", tc -> { ... });

// With settings
Hegel.test("description", Settings.builder().testCases(500).build(), tc -> { ... });

// Builder form (for databaseKey)
new Hegel(tc -> { ... })
    .settings(Settings.builder().testCases(100).build())
    .databaseKey("my_test")
    .run();
```

### Drawing Values

```java
long n     = tc.draw(integers());
long n     = tc.draw(integers(0, 100));       // bounded
int  n     = tc.draw(integers(0, 100).asInt());
double d   = tc.draw(floats());
double d   = tc.draw(floats().minValue(0.0).maxValue(1.0));
boolean b  = tc.draw(booleans());
String s   = tc.draw(text());
String s   = tc.draw(text().minSize(3).maxSize(20).ascii());
byte[] b   = tc.draw(binary().minSize(1).maxSize(256));
```

### Collections

```java
List<Long>       xs = tc.draw(lists(integers()));
List<Long>       xs = tc.draw(lists(integers(0, 10)).minSize(1).maxSize(5));
Map<Long, String> m = tc.draw(maps(integers(), text()));
Long             x  = tc.draw(optional(integers()));  // null or Long
Long             x  = tc.draw(sampledFrom(1L, 2L, 3L));
Long             x  = tc.draw(oneOf(integers(0, 5), integers(100, 200)));
```

### Format Generators

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
// map: transform a generated value
Generator<String> gen = integers(0, 100).map(n -> "item-" + n);

// filter: constrain values (retries up to 3 times, then assume())
Generator<Long> positive = integers(-100, 100).filter(n -> n > 0);

// flatMap: dependent generation
Generator<String> gen = integers(1, 10).flatMap(n ->
    text().minSize(n.intValue()).maxSize(n.intValue())
);
```

### Control

```java
tc.assume(condition);       // skip this input if false
tc.note("debug: " + value); // print during final shrunk replay
tc.target(score, "label");  // guide toward higher scores
```

### Settings

```java
Settings s = Settings.builder()
    .testCases(500)          // number of test cases
    .seed(42L)               // deterministic seed
    .derandomize(true)       // replay known examples only
    .database("/tmp/my.db")  // example database path ("" to disable)
    .verbosity(Settings.Verbosity.DEBUG)
    .suppressHealthCheck("too_slow")
    .build();
```

## Development

```bash
just test       # run tests (no coverage check)
just coverage   # run tests + enforce 100% line coverage
just conformance # run conformance tests against hegel-core
just check      # alias for coverage
```

## Architecture

```
src/main/java/dev/hegel/
├── Hegel.java              # Entry point: test(), run(), event loop
├── TestCase.java           # Handle passed to test functions
├── DataSource.java         # Interface abstracting protocol operations
├── ServerDataSource.java   # DataSource backed by real server stream
├── BasicGenerator.java     # Schema-based generator (server does all work)
├── Generator.java          # Interface: generate(), asBasic(), map(), filter(), flatMap()
├── Session.java            # Manages hegel-core subprocess + Connection
├── Settings.java           # Test settings builder
├── Labels.java             # Span label constants
├── StopTestException.java  # Signals test abort (overflow, etc.)
├── AssumeException.java    # Signals assume() failure
└── generators/
    └── Generators.java     # All built-in generators (integers, floats, lists, ...)

src/main/java/dev/hegel/protocol/
├── Connection.java         # Multiplexed IO: reader thread + stream registry
├── Stream.java             # Single logical stream (send/receive with buffering)
├── Packet.java             # Wire format: magic + CRC32 + streamId + msgId + payload
├── Cbor.java               # CBOR encode/decode via Jackson
└── HegelProtocolException  # Protocol-level errors
```

**Protocol flow:**
1. `Session.init()` spawns `uv tool run hegel --stdio` and handshakes
2. `Hegel.run()` sends `run_test` on the control stream
3. Server sends a `test_case` event on a new stream
4. `ServerDataSource` calls `generate()`, `start_span()`, etc. on that stream
5. Test body draws values; each `tc.draw()` calls `DataSource.generate(schema)`
6. On completion, `mark_complete` is sent; server may shrink and retry
7. `check_results` is called at the end; failures throw `AssertionError`

**Stream IDs:** Control stream = 0. `newStream()` assigns IDs via `(counter << 1) | 1`, so the first test stream has ID 3.
