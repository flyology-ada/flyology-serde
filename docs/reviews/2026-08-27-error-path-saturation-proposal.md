# Error-path saturation proposal

Date: 2026-08-27

Status: accepted and implemented after mandatory architecture, change, and
fix re-review. Final reviews report P0/P1/P2 none.

## Problem

`Policies.Maximum_Supported_Nesting` permits a logical nesting depth of 256,
and serializers accept an explicit operation limit up to that backend ceiling.
`Errors.Error_Info`, however, retains only 32 path elements. Today the 33rd
`Push_Field`, `Push_Index`, or `Push_Alternative` changes an otherwise clean
operation into `Depth_Exceeded`. Adapter path storage therefore silently
lowers usable logical nesting below the selected format and operation limits.

Diagnostic capacity is not traversal authority. Exhausting retained error-path
storage must not reject a value that the logical budget and backend accept.

## Proposed contract

Keep `Maximum_Path_Depth = 32` as the fixed retained-prefix capacity. Add the
exact visible component `Omitted_Path_Elements : Natural := 0` to
`Error_Info`. Its value is the number of currently active path elements deeper
than the retained prefix. Default construction and `Reset` both establish
zero.

For a clean `Error_Info`:

- a push while `Path_Length < Maximum_Path_Depth` appends the existing path
  element exactly as today;
- a push while the retained prefix is full increments
  `Omitted_Path_Elements` without changing `Code`, `Path_Length`, or `Path`;
- `Pop` first decrements `Omitted_Path_Elements`; only when it is zero does it
  remove the last retained path element; and
- `Reset` clears both retained and omitted path state.

If the omitted counter itself is already `Natural'Last`, another push reports
`Depth_Exceeded`. This is accounting exhaustion at the public type's numeric
limit, not the ordinary 32-element diagnostic-capacity case. Every supported
Serde traversal bounded by the 256-level logical ceiling is representable.

Pushes and `Pop` are strict no-ops after a primary error is latched. This
slightly narrows the old public `Pop` behavior so cleanup cannot erase a
captured failure path. Successful child traversal balances its push with one
pop while the error remains clean; a failed child retains the active prefix
and omitted count for the caller. The stored path is always the outermost
prefix in root-to-leaf order; `Omitted_Path_Elements > 0` explicitly says that
the error occurred beneath additional unretained elements. No suffix is
shifted into the fixed array.

`Path_Length` continues to mean the number of eligible entries in `Path`, not
the complete logical path depth. Existing callers that iterate
`1 .. Path_Length` remain valid. The new count is diagnostic metadata; it is
not an input budget, backend nesting count, wire identity, or persisted ABI.

The visible record has one defensive invariant while `Code = No_Error`:
`Omitted_Path_Elements > 0` requires
`Path_Length = Maximum_Path_Depth`. A push or `Pop` presented with a malformed
clean record latches `Invalid_State` without changing either path component.
When a primary code is already latched, push and `Pop` remain no-ops and the
primary code wins even if a caller previously malformed the visible record.

Add `Clear_Path (Item)` as a nonraising cleanup operation. It sets
`Path_Length` and `Omitted_Path_Elements` to zero and resets every slot in the
entire fixed `Path` array, including stale slots beyond `Path_Length`, while
preserving `Code`, `Input_Offset`, and `Offset_Unit`. The root serialization
and deserialization exception handlers call it after abort/rollback and before
reraising as best-effort cleanup of their formal state. Ada does not guarantee
copy-out of an `in out` actual on abnormal return, so this cannot promise any
caller-visible `Error_Info` state after a propagated exception. Every caller
that catches an escaping root or nested adapter exception must call `Reset` or
`Clear_Path` normally before inspecting or reusing the actual.

## Scope and compatibility

The change affects only bounded error-path bookkeeping and tests. It does not
change JSON or CBOR syntax, event grammar, format capabilities, logical
budgets, traversal order, adapter construction, output bytes, Type IR, Wire,
or generator authority. `Error_Info` is an experimental visible record, so the
new component is a source-visible shape change; repository search currently
finds no positional or named aggregate outside its own `Reset` body.
Every downstream Ada client must be rebuilt; this experimental API does not
claim binary compatibility with an old compiled `Error_Info` layout.

Map key-versus-value path roles are a separate P2 improvement and are not
folded into this saturation repair.

## Required evidence

Before commit:

1. Direct path tests prove default initialization, reset, the 32nd and 33rd
   pushes, nested omitted counts, balanced pops back through the retained
   prefix, prelatched push/pop no-ops, and a real primary beneath a truncated
   path. Saturation and prefix preservation are exercised separately through
   `Push_Index`, `Push_Field`, and `Push_Alternative`, including ordinary name
   truncation before path saturation.
2. One recursively composed `Adapters.Arrays` instance serializes and
   deserializes nested singleton arrays through both JSON and CBOR at depths
   32, 33, and 256 under matching explicit operation limits.
3. JSON and CBOR wrong-kind leaves at depth 33 retain 32 index elements,
   `Omitted_Path_Elements = 1`, and the backend's real primary status rather
   than `Depth_Exceeded`. Each case also proves candidate rollback, reader
   poison/abort, zero backend and budget depth, unchanged publication, and
   successful Reset reuse.
4. The same real wrong-kind cases at depth 256 retain the same 32-element
   prefix with `Omitted_Path_Elements = 224`. Exact reader input/value
   accounting, logical/backend depth cleanup, target rollback, poisoned-state
   rejection, and reset reuse are asserted for each format.
5. Successful traversals finish with `Path_Length = 0` and
   `Omitted_Path_Elements = 0`, exact output publication, balanced backend
   depth, and unchanged candidate publication rules.
6. A direct mixed field/alternative/index test uses arbitrary lower bounds and
   a long name, proving ordinary name truncation, retained outer-prefix order,
   exact omitted depth, and balanced cleanup. Each public push kind is also
   exercised as the first omitted element.
7. A direct overflow test fills the retained prefix, sets the visible omitted
   count to `Natural'Last`, pushes once, and proves `Depth_Exceeded`, unchanged
   path/count, no exception, and precedence of an already latched primary.
   Direct malformed-clean-record tests prove the defensive invariant for both
   push and `Pop`.
8. A depth-256 serialization failure in the counting preflight proves that the
   real JSON/CBOR writer publishes no bytes, aborts to `Poisoned`, retains the
   primary with a 32/224 path split, and succeeds after reset. Root
   serialization and deserialization exception injection proves abort,
   rollback, and nonpublication, then calls `Clear_Path` normally before
   inspecting or reusing the error actual.
9. Direct normal-return `Clear_Path` tests cover a clean populated path, a
   primary with exact offset/unit, caller-forged stale slots and malformed
   clean state, idempotence, complete fixed-array clearing, and preservation of
   code/offset/unit.
10. Root/tests, JSON dependency and isolation gates, generator gates, pinned
   formatting, line-length, shell, diff, and APM checks pass.

The architecture, implementation, and final staged diff each receive an
independent P0/P1/P2 review. Every finding is fixed before this proposal is
marked accepted.

## Review and verification record

The first architecture review found the required default for the omitted
count, ambiguous post-primary `Pop`, abnormal-return copy-out overclaiming,
the malformed visible-state invariant, and missing overflow/lifecycle
evidence. The revised proposal received two independent P0/P1/P2-none
architecture verdicts before implementation.

Change review found one P1: left-associative calculation of the last copied
name index could overflow for a short `String` ending at `Positive'Last`. The
implementation now evaluates `Name'First + (Retained - 1)` only when
`Retained > 0`; direct field and alternative tests use the maximum legal
bound. P2 findings strengthened exception-propagation, JSON and CBOR
poison/reset, complete retained-state comparison, malformed-primary, and
`Clear_Path` tests. Two independent final fix reviews report P0/P1/P2 none.

The final source state passes:

- root and test Alire builds plus the complete runtime test executable;
- both reviewed Flyology JSON dependency locks and ten lock-checker tests;
- test-hook elision and the isolated installed-client acceptance/rejection
  gate;
- twelve Python generator tests, the Ada generator build, scaffold tests,
  smoke/fault tests, release-marker and fixture-manifest checks, and the
  generated fixture build and executable;
- pinned GNATformat, 110-column, shell syntax, and Git diff checks; and
- APM 0.28.0 cache-only audit with all ten checks passing.
