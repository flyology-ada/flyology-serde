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
commit must leave the previously published application value unchanged.

The bounded core does not allocate. Text, bytes, field names, and variant names are copied into caller-supplied
buffers by a deserializer. A backend reports `Capacity_Exceeded` instead of allocating. Owned and borrowed modes
will be separate adapters over this contract. The current API yields no borrowed slice. A future zero-copy API
must expose input only within a callback or one deserializer step; neither an adapter nor a builder may retain it.

Every decoder is configured with explicit `Decode_Limits`. Backends enforce nesting, source input units, text and
byte lengths, and container lengths even when the source format has no such limits. Generated adapters separately
bound logical values and field work, so a compact source cannot cause unbounded construction. Input offsets are
zero-based, and each backend reports whether its unit is bytes, encoding code units, or Unicode code points.
The static deserialization adapter exposes its selected `Configured_Policy` and passes that policy into the
type-specific traversal; a backend constructor must be given the same or stricter limits.

## Event grammar

A serialization call emits exactly one value. Scalars and enumerations are complete values. A sequence is
`Begin_Sequence`, zero or more values, then `End_Sequence`. A map is `Begin_Map`, zero or more key/value pairs, then
`End_Map`; a backend may reject key kinds its format cannot represent. A record is `Begin_Record`, repeated
`Put_Field` plus one value, then `End_Record`. A variant is `Begin_Variant`, repeated `Put_Field` plus one value,
then `End_Variant`; the constructor name and payload are distinct. Begin calls may carry a known or unknown length.
Known lengths must match the emitted item count. Calls are strictly nested and a backend reports `Invalid_State`
for an illegal transition without emitting partial output where feasible.

A pull decoder mirrors that grammar. `Next_*` positions the source at one complete child and `End_*` is legal only
after all children have been consumed. `Skip_Value` consumes exactly one complete child and is the bounded mechanism
for an accepted unknown field or a duplicate value that policy discards.

Record policy explicitly chooses reject/ignore for unknown fields and reject/keep-first/keep-last for duplicates.
Missing-field handling and aliases are field-specific generated metadata: a missing required field fails, while a
declared default may be applied only when the adapter says so. Decode lookup uses generator-private local ordinals
or bounded name comparison. Those tokens are unstable build artifacts and never Type IR identities or wire tags.

## Scalar fidelity

The initial logical numeric events are exact signed and unsigned 64-bit integers and IEEE binary64. Binary64 events
preserve the value category, including NaN, infinity, and signed zero; a backend may return `Unsupported_Value` when
its format cannot preserve one. A generated adapter must prove that an Ada scalar fits an event exactly. Wider
integers, decimal or ordinary fixed point, non-binary64 floating point, and constrained scalar semantics require an
explicit exact adapter or a checked `Unsupported_Value` diagnostic. Generation and runtime must never truncate,
round, or infer a lossy conversion.

Records and enumerations carry logical names only. Stable wire family identifiers, field numbers, compatibility,
and canonical message encodings belong to the separate wire project.
