# Implementation Progress Notes

## Phase 1-2: Complete
- Read protocol spec, studied hegel-rust and hegel-typescript implementations
- Designed Perl API with explicit context passing and named arguments

## Phase 3-4: Protocol + Testing Infrastructure (In Progress)

### Working:
- Wire protocol (packet read/write with CRC32 validation)
- CBOR encoding/decoding with Tag 91 support (decode-only; client doesn't send Tag 91)
- Connection with demand-driven reader (no background threads)
- Stream multiplexing
- Session management (subprocess spawn, handshake)
- Test runner (test lifecycle, event loop, StopTest handling)
- TestCase (draw, assume, note, target, spans)
- Basic generators: integers, floats, booleans, text, binary, just, sampled_from
- Collection generators: lists (basic and compositional paths), tuples, hashmaps
- Combinators: map (preserves basicness), filter, flat_map, one_of, optional
- Format generators: emails, urls, domains, ip_addresses, dates, times, datetimes
- fixed_dictionaries for struct-like data

### Key Discoveries / Issues Found

1. **Tag 91 is decode-only**: The implementation guide's protocol skill says "All strings
   in CBOR payloads use Tag 91 (WTF-8). This is not optional." This is WRONG for the
   client side. The client sends standard CBOR with text strings (major type 3). Tag 91
   is only used by the server in its replies. The TypeScript agent report confirms:
   "tag 91 only received from server, never sent".

2. **Reply envelope format**: All protocol replies use `{"result": value}` / `{"error": msg}`
   format. The `request_cbor` method must extract the "result" field. This was not clear
   from the protocol docs or implementation guide.

3. **Event format**: Test events use `{event: "test_case", stream_id: N}` at the top
   level, NOT nested like `{test_case: {stream_id: N}}`. The protocol docs could be
   clearer about this.

4. **ACK format**: ACK replies to server requests must use `{"result": true}`, not `{}`.
   The server's PendingRequest.get() accesses payload["result"]. Sending an empty map
   causes a KeyError in the server.

5. **Perl CBOR hash key issue**: CBOR::XS can't use Tagged objects as hash keys (Perl
   stringifies them). Solution: use CBOR::XS's `filter` option for decoding, and
   `text_strings(1)` for encoding.

6. **Packet ordering**: The server interleaves packets from different streams. The
   demand-driven reader is essential for correct operation.

### TODO:
- Conformance test binaries
- Protocol-level unit tests
- Error handling (StopTest, error injection modes)
- Coverage infrastructure
- The `just` generator runs fewer test cases than requested (server optimization?)
