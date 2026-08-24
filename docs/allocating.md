# Explicit allocating modes

The bounded readers remain the primitive input API. They borrow immutable JSON or CBOR storage and copy decoded
text, bytes, field names, and alternatives into caller buffers. Allocating modes are explicit layers over that
contract; they do not change the deserializer event grammar, budget ownership, or transactional builder rules.

## Copied input snapshots

`Deserializers.JSON.Copied_Input` and `Deserializers.CBOR.Copied_Input` are generic over one statically configured
`Deserialization_Adapters` instance. `Deserialize` performs one synchronous whole-document transaction:

1. Return immediately when the incoming error is already set.
2. Compare the caller source length with the adapter's `Maximum_Input_Units` before allocation.
3. Copy the source to the standard Ada heap.
4. Construct and initialize the bounded borrowed reader with exactly `Adapter.Configured_Policy`.
5. Begin an unpublished candidate, traverse one value, finish the document, and commit only after all succeed.
6. Leave the reader scope, then free the source snapshot.

An over-limit source reports `Capacity_Exceeded` at zero-based byte offset `Maximum_Input_Units`, the first byte the
budget would reject. Candidate construction has not begun. `Storage_Error` from snapshot allocation propagates with
the target untouched. The facade copies its input; it does not take ownership or retain the caller array.

## Allocating destinations

`Adapters.Allocating_Text` produces `Ada.Strings.Unbounded.Unbounded_String` candidates.
`Adapters.Allocating_Bytes` exposes an `Ada.Containers.Vectors` byte vector. Both use the standard Ada heap and are
candidate operations, not publication operations. They must be called inside an application root builder whose
rollback releases or resets the candidate after every status or exception.

`Adapters.Allocating_Sequences` is a generic standard-heap vector candidate. It stages a complete local vector,
checks known and observed lengths against the operation's container-item limit and target index capacity, completes
`End_Sequence`, and then moves the vector into the unpublished target. A trusted known length may reserve
proportional storage up to the caller's decode limit. `Storage_Error` propagates for root abort and rollback.

Each decoded element is a fresh local value. Standard-vector reserve or growth may initialize and finalize retained
spare capacity and copy existing elements; `Append` copies the local value, which then finalizes. The adapter
therefore accepts definite, nonlimited elements whose `Initialize`, `Adjust`, and `Finalize` are nonraising and keep
ownership correct for every container copy and spare value. Limited, move-only, identity-owning, or otherwise
non-copy-safe resources use `Adapters.Arrays` with an application builder or a handwritten adapter. The target must
have no outstanding container cursor, reference, or iterator during replacement.

The first implementation deliberately layers over the bounded single-copy reader call. It eagerly allocates one
scratch buffer of `Maximum_Text_Length` or `Maximum_Byte_Length`, including a legal null range when the maximum is
zero. After a successful read it constructs a candidate containing exactly the decoded value or elements and frees
the scratch buffer; the standard containers may round their internal capacity. This uses
`O(configured maximum + decoded result)` transient memory, so callers should configure tight maxima. It is not a
streaming or proportionally growing decoder.

Format and configured-limit failures remain `Error_Info` statuses. Byte-vector index-capacity failure becomes
`Capacity_Exceeded`. `Storage_Error` from standard-heap scratch or result construction propagates after local
scratch cleanup; the enclosing root adapter then invokes `Rollback_Candidate`. A custom allocator, arena, or
proportional builder remains an application-provided adapter with explicit allocation and cleanup hooks.

The byte adapter also rejects `Maximum_Byte_Length` with `Capacity_Exceeded` before reading or changing its candidate
when the target's `Ada.Streams.Stream_Element_Offset` cannot represent the configured scratch extent. It rejects an
accepted length that the target's `Ada.Containers.Count_Type` cannot represent as well; neither conversion escapes as
`Constraint_Error` on a target with narrower container or stream index types.
