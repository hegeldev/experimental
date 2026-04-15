# Recovery Plan: DataSource Abstraction

## Remaining gaps from audit

- [x] Add DataSource record type to HegelFFI.hs
- [x] Refactor TestCase to hold DataSource instead of raw Stream
- [x] Implement serverDataSource (wraps existing stream-based protocol code)
- [x] Implement FakeDataSource for unit testing error paths
- [x] Write protocol unit tests using FakeDataSource (16 tests)
- [x] Add packet serialization round-trip tests
