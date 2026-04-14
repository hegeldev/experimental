# Changelog

## 0.1.0 - 2026-04-14

Initial release of hegel-java.

### Generators

- `integers()` — generate `long` values, with optional `minValue`/`maxValue` constraints and `.asInt()` convenience
- `floats()` — generate `double` values with optional bounds, `allowNan`, `allowInfinity`, `excludeMin`/`excludeMax`
- `booleans()` — generate `boolean` values
- `text()` — generate Unicode strings with optional `minSize`, `maxSize`, `codec`/`ascii()`
- `binary()` — generate `byte[]` with optional `minSize`/`maxSize`
- `characters()` — generate single Unicode characters (as one-codepoint strings) with optional `codec`, `minCodepoint`, `maxCodepoint`, `includeCharacters`, `excludeCharacters`
- `just(value)` — always return a fixed value
- `sampledFrom(v1, v2, ...)` — pick uniformly from a fixed list
- `lists(elements)` — generate `List<T>` with optional `minSize`/`maxSize`; uses schema composition when elements are basic
- `sets(elements)` — generate `Set<T>` (backed by `LinkedHashSet`) with unique elements; uses `"unique": true` schema when elements are basic, client-side `collection_reject` otherwise
- `maps(keys, values)` — generate `Map<K, V>` with optional `minSize`/`maxSize`
- `tuples(gen1, gen2, ...)` — generate fixed-length `Object[]`
- `oneOf(gen1, gen2, ...)` — pick uniformly from multiple generators
- `optional(element)` — generate a value or `null`
- `durations()` — generate `java.time.Duration` values with optional `minValue`/`maxValue`
- `emails()`, `urls()`, `domains()` — generate format-valid strings
- `ipv4Addresses()`, `ipv6Addresses()`, `ipAddresses()` — generate IP address strings
- `dates()`, `times()`, `datetimes()` — generate ISO 8601 date/time strings
- `fromRegex(pattern)` / `fromRegex(pattern, fullmatch)` — generate strings matching a regex
- `.map(fn)`, `.filter(pred)`, `.flatMap(fn)` — combinators on any generator

### Core API

- `Hegel.test(name, body)` and `Hegel.test(name, settings, body)` — run a property test
- `new Hegel(body).settings(...).databaseKey(...).run()` — builder form
- `TestCase.draw(generator)` — draw a value from a generator
- `TestCase.assume(condition)` — skip the current test case if false
- `TestCase.note(message)` — print a message during the final shrunk replay
- `TestCase.target(value, label)` — guide Hegel toward larger values

### Settings

- `Settings.builder().testCases(n).seed(s).derandomize(b).database(path).suppressHealthCheck(checks).build()`
- CI detection: auto-enables `derandomize` and disables database when running in CI

### Test utilities

- `HegelTestUtils.assertAllExamples(gen, pred)` — assert predicate holds for all generated values
- `HegelTestUtils.assertNoExamples(gen, pred)` — assert predicate holds for no generated values
- `HegelTestUtils.findAny(gen, pred)` — find and return any value satisfying predicate
- `HegelTestUtils.minimal(gen, pred)` — find the minimal value satisfying predicate (via shrinking)
