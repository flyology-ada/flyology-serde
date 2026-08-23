# CBOR backend

The CBOR backend maps the serde logical model onto one well-formed CBOR data item as defined by RFC 8949. It does
not define Flyology's message wire format, stable identities, schema evolution, framing, or transport behavior.

| Logical value | CBOR representation |
| --- | --- |
| null and Boolean | CBOR null, false, and true simple values |
| signed and unsigned integer | CBOR major type 0 or 1, using the shortest argument encoding |
| binary64 | CBOR IEEE 754 binary64, including nonfinite categories and signed zero |
| text | Definite-length CBOR UTF-8 text string |
| bytes | Definite-length CBOR byte string |
| none / some(value) | CBOR array `[0]` / `[1, value]` |
| sequence | CBOR array |
| map | CBOR map with arbitrary CBOR data-item keys |
| record | CBOR map whose keys are field-name text strings |
| enumeration | CBOR text string |
| variant | CBOR array `[alternative-name, payload-map]` |

The optional and variant envelopes are typed backend representation, not Type IR facts, CBOR semantic tags, or
wire identities. No private CBOR tag number is allocated. A reader interprets an envelope only when the type
adapter requests the corresponding logical operation. An optional envelope is a definite or indefinite array whose
first and only discriminator is the unsigned integer 0 or 1: 0 has no child and 1 has exactly one child. A variant
envelope is a definite or indefinite two-element array containing a text alternative name and a map payload. The
payload map may be definite or indefinite. A semantic tag at the envelope or child position takes precedence and
reports `Unsupported_Value`; another incompatible leading major type reports `Unexpected_Kind`. A wrong
discriminator, cardinality, child kind, or extra element reports `Invalid_Value`. A legal break that closes an
indefinite envelope at the wrong typed cardinality also reports `Invalid_Value`; a misplaced break in a definite
item reports `Syntax_Error`. `Syntax_Error` is otherwise reserved for CBOR that is not well formed.

Known sequence and map lengths use definite-length CBOR. Unknown lengths use an indefinite-length array or map and
the break stop code. Text and byte values are already complete at their logical event and are always emitted with a
definite length. Records and variants carry known field counts. The reader accepts definite and correctly chunked
indefinite text and byte strings, and definite or indefinite arrays and maps.

The initial writer uses the preferred shortest argument widths for integer arguments and lengths but always emits
binary64 for a binary64 event. It preserves every finite value, infinity, and signed zero; NaN remains NaN, without
a promise about NaN payload bits or signaling state beyond the core logical contract. Shortest argument widths are
only one part of RFC 8949 preferred serialization. Because binary64 is not shortened to binary16 or binary32, the
writer does not claim preferred serialization for the whole output. It also makes no core deterministic-encoding
claim: unknown-length containers are indefinite and record and map order follows the adapter. A reader accepts
well-formed nonpreferred argument widths and binary16, binary32, or binary64 float inputs. Promotion preserves every
finite shorter value exactly, retains infinity and signed zero, and retains the NaN category without promising its
payload.

The writer encodes the positive-infinity, negative-infinity, and NaN categories as binary64 bit patterns
`7FF0000000000000`, `FFF0000000000000`, and canonical quiet NaN `7FF8000000000000` respectively. A reader classifies
the sign, exponent, and significand bits before any Ada floating conversion. Only a proven-finite representation is
converted or promoted, so hostile nonfinite input never creates an invalid Ada floating value.

`Put_Signed` uses major type 0 for a nonnegative signed value and major type 1 for a negative value. `Read_Signed`
accepts either, but rejects a major-type-0 argument greater than `Integer_64'Last` and a major-type-1 value below
`Integer_64'First`. `Read_Unsigned` accepts only major type 0. `Peek_Kind` therefore follows a CBOR surface
convention: major type 0 is unsigned and major type 1 is signed even when a later signed adapter can accept the
major-type-0 value.

The bounded writer owns fixed-capacity bytes and copies them into a caller array. The explicitly allocating writer
uses a growable byte vector. The bounded pull reader borrows one immutable stream-element array for its lifetime and
copies decoded strings, byte strings, field names, and alternatives into caller-owned buffers. An allocating input
owner or allocating destination builder is a separate explicit owning facade over that traversal contract; the
reader never lends a source slice to an adapter or builder. While a reader exists, the source must not be mutated
through another alias or task. A byte offset is zero-based relative to the first source element, regardless of the
Ada array's lower bound.

Both writers use the JSON writer's incomplete/poison/reset lifecycle. Capacity exhaustion, allocation failure,
invalid grammar, invalid text, unsupported data, or a known-count mismatch poisons the writer and makes all partial
bytes unavailable as a complete item until `Reset`. An odd map and an incomplete optional or variant likewise never
become publishable output. The bounded writer reports capacity failure as a status. `Storage_Error` may propagate
from the explicitly allocating writer, but the writer is poisoned before propagation and its partial output must be
discarded.

One reader owns one `Decode_Budget`. It charges each input byte when consumed, each accepted logical value once,
each logical container item once, and decoded text or byte length before copying. A sequence element is one
container item, a map pair is one item, a record or variant field is one item, and a present optional child is one
item. Map keys and values are also their ordinary logical values. Structural names, discriminators, wrappers, and
indefinite-string chunks are not logical values. Indefinite string chunks are representation structure rather than
logical values. `Skip_Value` charges one discarded logical value and uses a separate bounded syntax stack and
per-depth counters for nested representation. Every skipped array, map, indefinite string, and semantic tag
increments syntax depth; a tag chain therefore cannot bypass `Maximum_Nesting_Depth`. Each array element, map pair,
and indefinite-string chunk counts against the applicable syntax item limit. Aggregate string length is
overflow-checked and bounded. The active logical depth plus raw skipped-subtree syntax depth must not exceed
`Maximum_Nesting_Depth`; a skip begun inside a nearly full logical container receives no independent depth
allowance. Each tag or other wrapper adds only constant work. Tags do not consume logical values, and chunks do not
consume logical text or byte events. Errors report zero-based byte offsets, unwind entered budget scopes, poison the
reader, and require reset.

Heads, arguments, and lengths are parsed as `Unsigned_64`. A scalar numeric argument stays in that domain and is
checked only against the requested logical scalar range, so `Read_Unsigned` can return `Unsigned_64'Last` regardless
of `Natural'Last`. Before a structural length, count, or index is narrowed or used in index arithmetic, the reader
compares it in the unsigned domain with `Natural'Last`, the configured limit, remaining input, and destination
capacity. No hostile structural value is narrowed first. Definite payloads are bounds-checked before access. An
indefinite string may require a validation/length pre-scan before caller-buffer copying; that scan is bounded by
`Input_Remaining`, does not charge or move the cursor, and is followed by one charged consumption pass. No phase
rescans a nested item, so total parser work is linear and bounded by a small constant multiple of the input-unit
ceiling.

An indefinite text or byte string contains only definite chunks of the same major type. Every text chunk is valid
UTF-8 independently, so a code point cannot cross a chunk boundary. Empty chunks are accepted within the same
bounds as other chunks.

The typed reader rejects every semantic tag, including self-described CBOR tag 55799, with `Unsupported_Value` and
rejects unassigned or unsupported simple values for ordinary logical reads. `Skip_Value` accepts and bounds a
well-formed tag wrapper and its content so an adapter can discard an unknown field; it checks basic CBOR
well-formedness but does not claim to validate the tag's unknown semantics. Generic CBOR-map pairs are delivered in
source order without collapse. Key equivalence and duplicate action are type-specific adapter policy, for which
rejecting duplicates is the recommended default. Record aliases resolving to the same component follow the record
duplicate policy.

`Peek_Kind` exposes only surface syntax: major type 0 is unsigned, major type 1 is signed, major types 2 and 3 are
bytes and text, major types 4 and 5 are sequence and map, false/true are Boolean, null is null, and binary16/32/64
are floating. Tags and unsupported simple values fail rather than being classified. There is no numeric coercion:
floating inputs are never integers, and logical enumeration, record, variant, and optional meaning comes only from
the typed operation requested by the adapter.

The CBOR backend reports every current `Format_Capabilities` member as true. Capabilities are stable for the entire
operation. An adapter must reject an unsupported or lossy mapping before the first output byte or destination
mutation.

The implementation follows the major-type, additional-information, indefinite-length, break, and floating-point
rules in [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949.html). It rejects reserved additional-information values,
standalone or misplaced breaks, truncated heads and payloads, odd indefinite maps, wrong string chunk types,
trailing bytes after the root item, arithmetic overflow, and all configured resource-limit violations.

The conformance matrix includes golden bytes for scalars and typed envelopes; nonpreferred integer and length
inputs; exact binary16 and binary32 promotion; positive and negative zero, infinities, and the NaN category;
unsigned-64 and signed-64 boundaries; definite and indefinite containers, envelopes, payloads, and strings; source-
order duplicate maps; tag-skip depth, including a skip entered from nearly maximum logical depth; oversized 64-bit
lengths; empty chunks; UTF-8 split across chunks; nested indefinite strings; reserved additional information;
invalid simple-value encodings; misplaced breaks; odd maps; truncation; trailing bytes; every independent resource
limit; and poison, unwind, and reset behavior after failure.
