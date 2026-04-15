# hegel-java — Claude Session Guide

## Build Commands

```bash
just test       # run all tests (no coverage enforcement)
just coverage   # run tests + enforce 100% line coverage (required to pass)
just check      # alias for coverage
just conformance # run conformance tests against hegel-core (requires just build-conformance first)
just build-conformance # build fat jar + shell wrapper scripts in bin/conformance/
mvn compile     # compile only
mvn package -DskipTests  # build jar without tests
```

Coverage requires 100% LINE coverage (not branch) excluding `dev/hegel/conformance/**`.
The check is configured in `pom.xml` under the `jacoco-maven-plugin` check execution.

## Project Layout

```
src/main/java/dev/hegel/
├── Hegel.java              # Entry point + event loop
├── Session.java            # Subprocess management + Connection lifecycle
├── ServerDataSource.java   # Protocol-backed DataSource
├── DataSource.java         # Interface for test operations
├── TestCase.java           # Handle passed to test functions
├── BasicGenerator.java     # Schema-composed generator
├── Generator.java          # Generator interface + default combinators
├── Settings.java           # Settings builder + CI detection
├── HegelTestUtils.java     # assertAllExamples, assertNoExamples, findAny, minimal
├── Labels.java             # Span label constants (LIST, SET, MAP, ONE_OF, etc.)
├── generators/Generators.java  # All built-in generators (integers, floats, text, binary,
│                               #   characters, just, sampledFrom, lists, sets, maps,
│                               #   tuples, oneOf, optional, durations, format generators)
└── protocol/               # Wire protocol (Packet, Connection, Stream, Cbor)

src/test/java/dev/hegel/
├── BasicIntegrationTest.java       # Core integration tests (real server)
├── GeneratorIntegrationTest.java   # Integration tests for all generator types and combinators
├── GeneratorUnitTest.java          # Generator unit tests using MockDataSource
├── HegelUnitTest.java              # Hegel.java internal method unit tests
├── ServerDataSourceTest.java       # ServerDataSource error path unit tests
├── SessionTest.java                # Session protocol + handshake unit tests
├── SettingsTest.java               # Settings builder + CI detection unit tests
└── protocol/ProtocolUnitTest.java  # Wire protocol unit tests (Packet, Stream, Connection)
```

## Architecture Notes

### Protocol
- hegel-core is spawned as a subprocess. `Session.init()` runs `uv tool run hegel --stdio`
- Override via `HEGEL_SERVER_COMMAND` env var (or `Session.envLookup` for tests)
- All communication is CBOR over stdout/stdin using a multiplexed packet protocol
- Packet format: 4-byte magic `HEGL` + 4-byte CRC32 + 4-byte streamId + 4-byte msgId + 4-byte length + payload + 1-byte terminator `\n`
- Stream IDs: control stream = 0; `newStream()` assigns `(counter << 1) | 1` (first = 3)
- Background reader thread routes packets to registered streams via `BlockingQueue`

### Session Singleton
- `Session.get()` lazily creates and caches one session per JVM
- `Session.reset()` destroys and clears the singleton (used in tests)
- `Session.testSession` (static, volatile) lets tests inject a fake Session into `Hegel.run()`
- `Session.envLookup` (static Function) can be overridden to inject the server command
- `Session.testServerLogDir` (static String) overrides the log directory in tests

### Generators
- `Generator<T>` interface: `generate(TestCase)` + `asBasic()` + `map()`/`filter()`/`flatMap()`
- `BasicGenerator<T>` = schema + transform lambda. Server generates via CBOR schema.
- Non-basic generators use span/collection protocol (start_span, new_collection, etc.)
- `ListGenerator.asBasic()` is called from `generateBasic()` when elements are basic
- `MapGenerator.generateCompositional()` is only called when keys or values are non-basic
- `SetGenerator.asBasic()` uses `"unique": true` flag on list schema (server enforces uniqueness)
- `SetGenerator.generateCompositional()` uses `collection_reject` for client-side duplicate detection
- `DurationGenerator` wraps integer schema (nanoseconds); `toNanos()` clamps overflow to `Long.MAX_VALUE`
- `CharactersGenerator` uses string schema with `min_size=1, max_size=1`; supports codec/codepoint filters

### Coverage Gotchas
- Stream.java line 83 (`bufferedRequests.add`): hit when `receiveReply()` encounters a non-reply packet. Requires the server to send a server-initiated request BEFORE sending the actual reply.
- Stream.java lines 105-106 (`bufferedReplies.put`): hit when `receiveRequest()` encounters a reply packet. Requires calling `receiveRequest()` before consuming a pending reply.
- Stream.java lines 143-144 (SERVER_EXITED in receiveReply): call `stream.serverExited()` directly (package-private), then `receiveReply()`.
- Stream.java line 166 (close IOException): kill server (serverExited=true), then call `stream.close()`.
- ServerDataSource lines 45-47, 53-55: kill server before/during generate().
- ServerDataSource line 84 (return decoded): server returns `{"status": "ok"}` (no result/error).
- ServerDataSource line 159 (markComplete exception): kill server before markComplete().
- Session lines 100-103: use `Session.envLookup = v -> "nonexistent_command"` + `Session.reset()` + `Session.get()`.
- Session line 197: set `Session.testServerLogDir = "/dev/null/cannot_create"` (triggers IOException on createDirectories).

## Testing Conventions

### Real Server Tests
Integration tests use the real hegel-core server. The global `Session` singleton is shared across tests in the JVM. Tests that reset the session (`Session.reset()`) must restore it in a `finally` block.

### FakeServer Pattern
Protocol unit tests use piped streams to simulate hegel-core:
```java
// Client-side: PipedInputStream (from serverOut) + PipedOutputStream (to serverIn)
// Server-side: PipedInputStream (serverIn) + PipedOutputStream (serverOut)
// Connection.create(clientIn, clientOut) routes packets; server thread reads/writes directly
```
Stream ID for `connection.newStream()`: always starts at 3 (first call), 5 (second), etc.

### MockDataSource
`GeneratorUnitTest.MockDataSource` provides pre-programmed `JsonNode` responses for testing generator transforms without a server. Add with `.withResponse(node)`.

### Hegel.testSession Injection
`HegelUnitTest` injects a fake `Session` via `Hegel.testSession` to test `Hegel.run()` error paths without spawning a real server. Always reset in `@AfterEach`.

## Key Gotchas

1. **Session singleton cleanup**: After `Session.reset()`, always call `Session.get()` in `finally` to restore for subsequent tests.

2. **Stream IDs**: `connection.newStream()` uses `(counter << 1) | 1`. First call: counter=1, ID=3. Second: counter=2, ID=5. The FakeServer must use the correct stream ID when sending packets.

3. **PipedStream buffer size**: Default (1024 bytes) can block on large CBOR payloads. Always use `new PipedInputStream(serverOut, 8192)` in tests.

4. **serverExited race**: After `serverOut.close()`, allow ~200ms `Thread.sleep()` for the reader thread to detect EOF and set `serverExited=true`.

5. **receiveReply vs sendRequest failure**: If `serverExited=true` when `sendRequest()` is called, it throws immediately (lines 45-47). To hit lines 53-55 (receiveReply failure), the server must read the request FIRST, then close.

6. **CI detection**: `Settings.isInCI()` reads env vars (CI, GITHUB_ACTIONS, etc.). Tests use `Settings.testCiOverride` and `Settings.isInCIFromEnv(Function)` for deterministic control.

7. **CBOR schema field names**: Must exactly match hegel-core expectations. `"binary"` not `"bytes"`, `"constant"` not `"just"`, `"ipv4"` not `"ip_address"`.

8. **Float schema**: `allow_nan`/`allow_infinity` depend on `!hasMin && !hasMax` when not explicitly set. Three branches: no constraints, only-max, only-min each produce different defaults.
