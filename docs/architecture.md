# Architecture

The dependency direction is:

```text
Ada value
  <-> type-specific adapter
  <-> Flyology_Serde logical events
  <-> format backend
  <-> JSON, CBOR, or another representation
```

Type adapters own Ada traversal, subtype validation, missing and duplicate field policy, and destination
construction. Format backends own parsing, escaping, concrete number forms, input offsets, and output storage.

Serialization and deserialization are separate capabilities. Serialization reads an existing value through an
`in` parameter. Deserialization targets an application-owned builder so private, limited, controlled, and
indefinite types are not forced through assignment or default construction. A builder holds an unpublished
candidate. `Begin_Candidate` initializes it, `Commit_Candidate` is the only operation that publishes it, and
`Rollback_Candidate` releases all candidate-owned resources after any reported failure or exception. A failed
commit must leave the previously published application value unchanged. `Deserialization_Adapters.Deserialize` is
a whole-document root transaction: after value traversal it calls the backend's abstract `Finish_Document`, then
commits only if exact-root and trailing-input validation succeed. Nested combinators call their candidate traversal
directly and never finish a document. On every reported failure or exception, the root first calls the backend's
nonraising, idempotent `Abort_Document`, then rolls back the unpublished candidate. Abort unwinds every entered
backend scope while preserving an earlier status and poisons the operation; the backend's explicit reset is the only
route to reuse. A raised adapter exception remains the primary exception.

The bounded core does not allocate. Text, bytes, field names, and variant names are copied into caller-supplied
buffers by a deserializer. A backend reports `Capacity_Exceeded` instead of allocating. The JSON and CBOR
`Copied_Input` generic facades make a standard-heap snapshot, run one synchronous root transaction, finalize the
borrowed reader, and then free the snapshot. They preflight `Maximum_Input_Units` before allocation. The current API
yields no borrowed slice. A future zero-copy API must expose input only within a callback or one deserializer step;
neither an adapter nor a builder may retain it.

`Adapters.Allocating_Text` and `Adapters.Allocating_Bytes` are explicitly named standard-heap candidate adapters.
They eagerly allocate one scratch buffer equal to the configured text or byte maximum, decode through the bounded
copy API, then construct a candidate containing exactly the decoded value; the container implementation may round
its internal capacity. Tight limits are therefore important. `Storage_Error` propagates after scratch cleanup so
the outer root transaction can roll back; format capacity remains a status.
Application-specific allocating builders may instead expose allocator and cleanup hooks as generic actuals.

Every decoder is configured with explicit `Decode_Limits`. Backends enforce nesting, source input units, logical
values, text and byte lengths, and container items even when the source format has no such limits. Generated
adapters separately bound schema work and candidate capacity, so a compact source cannot cause unbounded
construction. Input offsets are zero-based, and each backend reports whether its unit is bytes, encoding code
units, or Unicode code points.
The static deserialization adapter exposes its selected `Configured_Policy` and passes that policy into the
type-specific traversal; a backend constructor must be given the same or stricter limits.

One concrete deserializer owns exactly one `Decode_Budget`. The backend charges raw input units as its cursor
advances, one logical value when it accepts that value, one container item when it accepts that item, and text/byte
length before copying. Generated adapters do not charge this budget. They bound separate schema work such as field
lookup and candidate capacity. A backend operation may unwind scopes when it detects its own failure; root abort
must also unwind scopes left open by an adapter failure or exception. Each successfully entered scope is unwound
exactly once even when an error is already latched, and unwind preserves the primary error.

For JSON and CBOR, input units and error offsets are zero-based bytes. Any future backend that uses code units or
code points must select that unit at construction and retain it for the operation. Capabilities are likewise stable
for one backend configuration and operation. An adapter must reject a required unsupported or lossy capability
before its first output event or destination mutation.

Adapter-generated semantic errors do not claim a token-start offset that the pull interface cannot recover. The
mandatory root transaction's `Abort_Document` attaches the backend's current next-unread position and unit when the
error has no offset. JSON and CBOR therefore attach a byte position after the typed name or constructor read.

## Event grammar

A serialization call emits exactly one value. Scalars and enumerations are complete values. A sequence is
`Begin_Sequence`, zero or more values, then `End_Sequence`. A map is `Begin_Map`, zero or more key/value pairs, then
`End_Map`; a backend may reject key kinds its format cannot represent. A record is `Begin_Record`, repeated
`Put_Field` plus one value, then `End_Record`. A variant is `Begin_Variant`, repeated `Put_Field` plus one value,
then `End_Variant`; the constructor name and payload are distinct. Begin calls may carry a known or unknown length.
Known lengths must match the emitted item count. Calls are strictly nested and a backend reports `Invalid_State`
for an illegal transition without emitting partial output where feasible.

An optional is `Begin_Optional`, zero children when absent or exactly one child when present, then `End_Optional`.
This logical distinction allows a backend to preserve nested optionals rather than conflating absence with null.
`Lossless_Optionals` means every nesting and child combination is distinct, including none, some(none), and
some(null); a backend that cannot guarantee all combinations reports false.

A pull decoder mirrors that grammar. `Next_*` positions the source at one complete child and `End_*` is legal only
after all children have been consumed. `Skip_Value` consumes exactly one complete child and is the bounded mechanism
for an accepted unknown field or a duplicate value that policy discards.

Record policy explicitly chooses reject/ignore for unknown fields and reject/keep-first/keep-last for duplicates.
Missing-field handling and aliases are field-specific generated metadata: a missing required field fails, while a
declared default may be applied only when the adapter says so. Decode lookup uses generator-private local ordinals
or bounded name comparison. Those tokens are unstable build artifacts and never Type IR identities or wire tags.
`Adapters.Records` bounds schema work with `Maximum_Fields`, `Maximum_Field_Name_Length`, and a per-field alias
maximum. It validates primary and alias metadata before the first format event. Decode performs a full field scan so
an ambiguous handwritten matcher fails before duplicate handling and before consuming the value. Unknown-ignore and
keep-first each call `Skip_Value` once; keep-last calls the field hook once with explicit replacement ownership.
After `End_Record`, missing hooks run in ordinal order and a final hook checks cross-field and discriminant-dependent
invariants. The generic covers records with at least one flattened logical field; null records and generated exact
variant selection require distinct adapters rather than invented ordinals.

The reviewed enumeration design has an independent maximum literal count and bounded type, literal, and alias
names. It iterates checked local ordinal tables rather than representation values or positions. Declared names must
map uniquely to their own literal; handwritten matchers may accept extra names, but runtime ambiguity is an
application metadata error and no match is an invalid value. Literal contents do not become a structural path
element; the enclosing field/index path and backend offset identify the failure.

The reviewed finite-variant design independently bounds all alternatives, all global field declarations, and fields
selected by one alternative. One global field ordinal represents one logical declaration: a common component keeps
one ordinal across leaf alternatives, while distinct branch declarations keep distinct ordinals even when their
names match. Name uniqueness is checked only within one alternative. Filtered global ordinal order controls output
and missing hooks, and unused field ordinals are rejected. An `Alternative_Element` path component identifies the
selected constructor above any field path.

A selected zero-known-field alternative still traverses every incoming payload entry as an unknown field and either
rejects or skips its value once. A separate nullary-variant combinator preserves `Begin_Variant (..., 0)` and
`End_Variant`; mapping a nullary sum to enumeration is an explicit overlay policy because it changes the logical kind
and JSON/CBOR representation.

## Scalar fidelity

The initial logical numeric events are exact signed and unsigned 64-bit integers and IEEE binary64. A binary64 event
uses a definite private value containing a semantic category and an always-valid finite Ada slot. It never passes an
invalid Ada floating representation across a subprogram boundary. Default initialization is finite positive zero;
`Make_Finite` preserves the sign bit of zero. The three nonfinite categories are positive infinity, negative
infinity, and NaN, without a NaN payload or signaling-state promise. `Nonfinite_Float_64` means that a backend
accepts and returns all three categories. A backend may return `Unsupported_Value` when its format cannot preserve
them. A generated adapter must prove that an Ada scalar fits an event exactly. Wider
integers, decimal or ordinary fixed point, non-binary64 floating point, and constrained scalar semantics require an
explicit exact adapter or a checked `Unsupported_Value` diagnostic. Generation and runtime must never truncate,
round, or infer a lossy conversion.

Records and enumerations carry logical names only. Stable wire family identifiers, field numbers, compatibility,
and canonical message encodings belong to the separate wire project.
