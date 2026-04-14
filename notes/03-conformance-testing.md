# Conformance Testing Notes

## Status

### Passing (8 of 14):
- BooleanConformance
- IntegerConformance
- BinaryConformance
- SampledFromConformance
- ListConformance[basic]
- DictConformance[basic]
- (Error handling tests pending)

### Known Issues:

#### FloatConformance
- When allow_nan/allow_infinity are null (use server defaults), NaN/Infinity
  must be generated. With 500 test cases they appear, but the conformance
  framework might not wait long enough or might use different default counts.
- JSON::PP::Boolean false values from JSON decoding are `defined` in Perl,
  causing `exclude_min => false` to be passed to the schema when it should
  be omitted. Fix: check truthiness, not definedness, for boolean params.

#### TextConformance
- CBOR-decoded strings are byte strings in Perl. Must use `Encode::decode('UTF-8', $val)`
  before `split` to get proper Unicode codepoints. Without this, multi-byte
  characters are split into individual bytes.

#### ListConformance[non_basic] with unique=True
- The non_basic path with uniqueness uses `collection_reject` for duplicates.
- The server's "simplest test case" always generates zeros, causing infinite
  rejection loops. The server should eventually send StopTest when data is
  exhausted, but this takes many iterations.
- Large min_size (48+) with non_basic elements is inherently slow due to
  6+ protocol round-trips per element attempt.

#### DictConformance[non_basic]
- Same duplicate key issue as unique lists.
- Current fix: silently overwrite duplicate keys (no collection_reject).
- This can cause dict size < min_size, failing the conformance check.

## Perl-Specific CBOR Issues

1. **String/number ambiguity**: CBOR::XS decodes integers that look like
   integers, but JSON::XS may encode them as strings. Always force numeric
   context with `+ 0` before JSON encoding.

2. **JSON boolean handling**: `JSON::PP::Boolean` false values are `defined`
   in Perl. When checking optional boolean params from JSON, use truthiness
   (`if ($val)`) not definedness (`if (defined $val)`).

3. **UTF-8 string handling**: CBOR-decoded strings don't have Perl's UTF-8
   flag set. Must `Encode::decode('UTF-8', ...)` before Unicode operations.

## Implementation Guide Suggestions

1. The conformance test chapter should warn about the "simplest test case"
   behavior: the server's first test case always generates minimal values
   (zeros). Implementations with uniqueness constraints will get infinite
   rejection loops unless they handle this (e.g., assume(false) after N retries).

2. The CBOR gotchas chapter should mention that decoded values may not have
   language-specific type flags (e.g., Perl's UTF-8 flag, Python's str vs bytes).

3. The conformance binary section should note that JSON boolean params
   (true/false from Python) need careful handling in languages where
   `false` is a defined truthy-or-falsy object rather than a plain 0/empty.
