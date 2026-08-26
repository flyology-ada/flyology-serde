# Flyology JSON backend assessment

Date: 2026-08-26

Status: corrected pre-integration architecture proposal; no dependency or runtime change is authorized by this
record.

## Reviewed release

This assessment covers the indexed `flyology_json=0.1.0-dev` release from source commit
`f8a4a0331a03552733e7bd8531552ba0c21f8997` and Flyology Alire-index commit
`5693988242276f7a93b5034383764f87f5a42890`. The release exposes the trusted incremental `Parsing`
`Step`/`Drain` event grammar, exact number lexemes, decoded Unicode fragments, duplicate-name policy,
transactional `Writing`, and checked signed and unsigned integer conversion. Its release record explicitly
states that the trusted core has no accounting or budget surface for untrusted consumer integration.

## Serde boundary

The event grammar, exact source byte offsets, arbitrary input bounds, immediate raw-range lifetime, explicit
profile identity, and parser reset/abort lifecycle are compatible with a future JSON-to-Serde adapter. They do
not transfer JSON syntax, duplicate-name, destination, or parser authority into Serde. Serde continues to own its
format-neutral traversal, logical optional/variant mapping, candidate commit/abort, error paths, and backend
resource policy.

The current `Flyology_Serde.Deserializers.JSON.Reader` owns exactly one `Decode_Budget`. It charges input units,
logical values, nesting, container items, and text/byte lengths. Its source scanning is coupled to the remaining
input-unit bound; the budget has no independent parser-work or total-work category. Flyology JSON itself is trusted
code. The input may be untrusted, and its caller-driven `Step` boundary permits Serde to bound how much input one
call can inspect without requiring a parser-internal accounting hook.

The first adapter uses one-byte input windows. Before exposing a new byte, it consumes that byte exactly once from
the existing input budget and records the charged window. If `Step` publishes a zero-consumption event, the adapter
reuses the same already charged byte; it does not charge again. When the parser consumes it, the adapter advances
the source offset and clears the window. End-of-input calls use an empty array and no input charge. This may charge
one examined byte that a rejecting parser leaves unconsumed, but never charges one source byte twice and never lets
the parser inspect beyond the admitted input frontier.

Each call can inspect at most one newly admitted byte. The exact zero-progress ceiling is
`Event_Kind'Pos (Event_Kind'Last) + 1`, currently 17; it is derived from the closed event vocabulary rather than
selected as an independent capacity. After a normal `Step`, positive `Consumed` resets the consecutive counter.
`Event_Ready` with zero `Consumed` increments it. The adapter never calls `Step` with empty nonfinal input, and
`Need_Input` on a nonempty window must consume that byte. `Document_Complete`, `Step_Failed`, and `Call_Rejected`
are terminal for that parser operation and permit no next `Step`. Exceeding the ceiling latches Serde
`Invalid_State` at the call's `Input_Origin`, aborts the parser, clears provisional adapter state, and refunds no
charge.

The ceiling is conservative: a zero-consumption event advances one phase of the closed grammar. Another token
fragment, container, or value requires input consumption; an inline decoded scalar is the bounded completion of a
previously consumed escape; and document, string, name, number, and container boundary events form finite sequences.
Direct tests must record the maximum observed zero-consumption run for every complete one-byte fixture, malformed
fixture, and event kind, and inject the exact ceiling and one-over transition into the adapter guard. With
`Preserve_Unchecked`, no duplicate index or retained-name comparison occurs in the parser. Total parser calls are
therefore bounded by admitted input bytes plus the exact zero-progress ceiling per consumed-byte/terminal interval.
This is the initial correctness profile. A later batched `Drain` optimization requires separate accounting,
lifetime, transcript-parity, and performance review.

Serde record and map adapters support reject, keep-first, and keep-last duplicate policies, and presentation aliases
may collide independently of raw JSON-name equality. A general future adapter must instantiate Flyology JSON with
static `Preserve_Unchecked`, expose every member in source order, and charge/enforce duplicate and alias policy in
Serde. A `Reject_Duplicates` parser instance may be used only by an adapter that capability-rejects every incompatible
Serde policy before byte zero or destination mutation. Flyology JSON duplicate-index work is therefore avoidable;
the initial adapter always uses `Preserve_Unchecked`.

The adapter freezes an explicit strict profile before byte zero: RFC 8259 syntax version 1, Unicode scalars version
1, `No_Extensions` compatibility version 1, BOM rejection, `Preserve_Unchecked`, and any-value top level. It does not
enable comments or trailing commas. Every event is consumed synchronously while its one-byte producing window is
alive. Raw name/string fragments are copied before the next parser call; inline decoded scalars are copied from the
event value. No raw range or derived access value is retained.

Incremental text assembly remains transactional at the existing Reader boundary. At name/string begin, the adapter
sets the destination to blanks and its published length to zero, matching the handwritten reader. Before copying
each raw or inline-decoded fragment, it uses checked cumulative-length arithmetic, applies `Check_Text_Length` for a
text value, verifies caller capacity, and only then copies that entire fragment. A later fragment, UTF-8, capacity,
budget, parser, or lifecycle failure clears the complete destination back to blanks and republishes length zero
before normal return. Field, enumeration, and variant names follow the same all-or-cleared rule; decoded byte values
retain their existing all-or-cleared transaction.

Exact number fragments are copied into the current operation-local fixed candidate only after checked cumulative
length and capacity validation: 32 bytes for signed/unsigned conversion and 768 bytes for binary64 conversion. A
denied fragment is not partially copied, and a later failure leaves the scalar output at the same default value as
the handwritten reader. Split-fragment tests compare both successful values and every failed caller buffer/length or
scalar output against that oracle.

The event engine remains private behind the existing `Flyology_Serde.Deserializers.JSON.Reader` API. The current
handwritten reader remains a byte-for-byte and diagnostic oracle until all JSON, adapter, malformed, arbitrary-bound,
budget, abort/reset, and allocation tests pass against both engines. Root candidate commit still occurs only after
the existing `Finish_Document`; Flyology JSON's `Document_Complete` is necessary but does not publish a Serde
candidate. Serde error-path ownership, logical optional/variant envelopes, bytes encoding, and duplicate/alias
policy remain unchanged.

The wrapper maps Flyology JSON lifecycle outcomes explicitly. `Step_Failed` copies the retained JSON diagnostic once
into the existing Serde error code and zero-based byte offset, latches it as primary, clears the charged-window,
event, and token candidates without refund, and makes no further parser call except cleanup. `Call_Rejected` maps to
Serde `Invalid_State` at `Input_Origin`. A prelatched Serde error prevents `Step` entirely.

`Reader.Abort_Document` preserves any prelatched Serde primary. If none exists and the JSON parser has a retained
`Failure_Pending` or `Failed` diagnostic that has not already been copied, it copies that diagnostic once; otherwise
it leaves `No_Error` unchanged, preserving the current public Reader behavior. It then calls Flyology JSON
`Abort_Document` idempotently, clears every cached window/event/token candidate, unwinds each entered Serde budget
scope exactly once, and leaves the reader failed until `Reset`; no accepted charge is refunded. The zero-progress
guard latches `Invalid_State` before taking this abort path, so cleanup cannot replace it.

`Reset` first terminalizes and cleans any old active or `Failure_Pending` parser operation with normal primary
precedence, then deliberately discards every diagnostic belonging to that old operation. A reported or unreported
old parse failure is therefore never a reset blocker and never leaks into the new operation. Only a new cleanup
mechanism defect or failure while applying the new Flyology JSON `Reset`/`Initialize` and profile may prevent
readiness; because the public `Reset` has no error output, such a failure leaves the Reader poisoned and does not
retroactively mutate a caller's prior `Error_Info`. Reset applies the same explicit profile, installs a fresh
`Decode_Budget`, and publishes Reader readiness only after every new-operation step succeeds. Direct tests reset
from an unreported JSON `Failure_Pending` and after a reported `Step_Failed`, then require readiness, a fresh budget,
byte offset zero, and no stale diagnostic leakage. JSON cleanup is nonraising and allocation-free. An unexpected
adapter programming exception performs the same cleanup and then remains an exception; it is never reported as
malformed input or allowed to replace an already latched input diagnostic.

The transactional writer is not adopted in this parser milestone. Serde's current JSON writer preserves its
established logical envelope bytes and publication behavior. A later writer adapter may use Flyology JSON when a
separate change proves byte-for-byte compatibility, destination charging ownership, preflight behavior, and
abort/finalization precedence.

## Decision

- Keep CBOR unchanged and keep the current JSON reader as the conformance oracle during the parser migration.
- After explicit dependency authorization, add exactly `flyology_json = "0.1.0-dev"` from the Flyology Alire index;
  do not add a Git/path pin or a generator dependency.
- Implement the one-byte `Step` driver and event-to-existing-Reader-state translation privately before selecting a
  batched path or deleting handwritten parsing code.
- Preserve all current public JSON/CBOR APIs, logical bytes, diagnostics, offsets, budget outcomes, and fixtures.
- Keep this runtime work independent of Ada Type IR, generator attestation, Wire, Flyology tasking, and remoting.

## Review gate

Architecture review must confirm the one-byte admission proof, bounded zero-progress transitions, event/fragment
lifetime, static duplicate/profile selection, exact offset mapping, candidate nonpublication, and reset/abort
precedence. The change review must compare the complete existing JSON suite under both engines, including failed
output preservation, and add direct one-byte charge and zero-progress traces. Any dependency or adapter
implementation still requires explicit dependency authorization and its own final change review.
