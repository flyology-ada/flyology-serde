# JSON backend

The JSON backend maps every supported serde logical value losslessly using UTF-8 JSON. It is deterministic for one
event stream but does not sort record fields or claim RFC canonicalization. Nonfinite binary64 values are outside
the supported JSON capability.

| Logical value | JSON representation |
| --- | --- |
| null, Boolean, signed/unsigned integer, finite binary64, text | Corresponding JSON scalar |
| bytes | `{"$bytes":"<uppercase hexadecimal>"}` |
| none / some(value) | `[0]` / `[1,value]` |
| sequence | JSON array |
| map | Array of `[key,value]` pairs, preserving arbitrary key types and order |
| record | JSON object in adapter field order |
| enumeration | JSON string literal |
| variant | `["<alternative>", {<payload fields>}]` |

The tags above are backend representation, not Type IR or wire identities. A reader interprets them only when the
type adapter requests the corresponding logical kind.

`Bounded_Writer` owns fixed-capacity storage and exposes output only through `Copy_Output` into a caller buffer;
an incomplete or failed writer reports `Invalid_State`, returns length zero, and copies no prefix. There is no
unconstrained-string convenience result on the bounded path. `Allocating_Writer` uses `Ada.Strings.Unbounded`
explicitly and offers `Output`, which returns an empty string until the writer is complete. Both writers are
poisoned after a capacity, grammar, text, or unsupported-value error and must be reset before reuse. Heap exhaustion
during mutation of the explicitly allocating writer poisons it and propagates `Storage_Error`; it is not reported
as a format capacity status. A later `Output` call may independently exhaust memory while copying a completed
buffer; that exception leaves the completed writer retryable.

A balanced direct event traversal remains `Active` and unpublishable until `Finish_Document` succeeds. Calling
`Finish_Document` without exactly one balanced root poisons the writer. A second finish or any event after `Finished`
reports `Invalid_State` while preserving the completed output. An event after `Poisoned` likewise reports
`Invalid_State`; only `Reset` returns to `Ready`. A prelatched error makes every event and finish a strict no-op.
`Abort_Document` is nonraising and idempotent, discards traversal state, and leaves the writer `Poisoned`; aborting a
finished writer intentionally revokes publication. `Copy_Output` before finish or after failure returns no prefix.

`Deserializers.JSON.Reader` is the bounded pull reader. Its access discriminant borrows one immutable input string
for the reader's lifetime under Ada accessibility checks. The source owner must also exclude mutation through any
other alias or task during traversal. The reader returns no borrowed slice: decoded text, bytes, field names, and
variant names are copied into caller-owned buffers. `Initialize` is required before the first event.
After exactly one root value, `Finish_Document` consumes trailing JSON whitespace and rejects any other trailing
input; only then does `Is_Complete` become true. Any parse, capacity, budget, or protocol error unwinds all entered
budget scopes, poisons the reader, and requires `Reset`, which restarts at byte offset zero with a fresh budget.
If an adapter reports or raises while it owns an open traversal scope, the root transaction invokes
`Abort_Document`; abort is nonraising and idempotent, unwinds the remaining scopes without replacing the primary
status, and leaves the reader poisoned until reset.

`Deserializers.JSON.Copied_Input` is a generic synchronous snapshot facade around a complete root adapter. It checks
the caller input length against `Maximum_Input_Units` before allocation, copies the string on the standard Ada heap,
runs the root transaction with exactly the adapter's configured policy, leaves the borrowed reader scope, and frees
the copy on every status or exception path. It copies rather than taking caller ownership. An over-limit preflight
reports `Capacity_Exceeded` at the first disallowed zero-based byte offset and never begins a candidate.

The reader owns exactly one `Decode_Budget`. Cursor movement charges UTF-8 input bytes, accepting a logical value
charges one value, accepting a logical container child charges one item at the active depth, and decoded text or
byte length is checked before copying. Errors use zero-based byte offsets. `Skip_Value` charges exactly its one
discarded logical value; nested JSON representation nodes are not charged as logical values or containers. Because
the adapter has discarded the expected Ada kind, the raw subtree is separately checked against the configured
per-container item, decoded-string, and input-work ceilings. Its raw syntax depth plus the reader's active logical
depth must remain within the same configured nesting limit.

JSON syntax-level peeking cannot recover the adapter's expected logical kind: a string may be text or an
enumeration, an array may be a sequence, map, optional, or variant, and an object may be a record or bytes. Therefore
`Peek_Kind` reports a JSON surface convention rather than recovering the adapter's logical kind: fractional or
exponent numbers are float, negative integers are signed, nonnegative integers are unsigned, strings are text,
arrays are sequences, and objects are records. The type adapter selects the typed read operation, which validates
the full representation. Whitespace is accepted between JSON structural tokens. Byte payloads use an unescaped
hexadecimal JSON string; this is the backend's exact tagged representation, not a general JSON object coercion.

Strings and names must be valid UTF-8. Control characters, quotation marks, and reverse solidus are escaped. Other
valid UTF-8 bytes are preserved. Byte values use uppercase hexadecimal. `Put_Float_64` rejects a nonfinite category
before emitting any bytes for that event, without constructing an invalid Ada float. An adapter that requires
nonfinite support checks the backend capability before its traversal's first event. Finite values use 17 significant
decimal digits for bit-exact binary64 round trips; signed zero and adjacent representable values are retained as
JSON numbers.
