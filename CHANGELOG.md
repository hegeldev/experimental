# Changelog

## 0.1.0 (Unreleased)

Initial release.

- Haskell FFI protocol layer implementing the Hegel wire protocol (v0.10)
- CBOR encoding/decoding via Haskell's `cborg` library
- Stream multiplexing and connection management
- Support for all primitive generators (integers, floats, booleans, text, binary)
- Support for format generators (emails, URLs, domains, IP addresses, dates, times, datetimes)
- Regex generator support
- Collection generators (lists, tuples, dicts)
- Combinators: map, filter, flatMap, oneOf, optional
- Control functions: assume, note, target
- Test runner with `runHegelTest` and `runHegelTests`
- Basic/composite generator distinction with schema composition
