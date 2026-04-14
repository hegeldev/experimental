# Recovery Plan: DataSource Abstraction

## Remaining gaps from audit

- [ ] Add DataSource record type to HegelFFI.hs
- [ ] Refactor TestCase to hold DataSource instead of raw Stream
- [ ] Implement serverDataSource (wraps existing stream-based protocol code)
- [ ] Implement FakeDataSource for unit testing error paths
- [ ] Write protocol unit tests using FakeDataSource
- [ ] Add packet serialization round-trip tests
