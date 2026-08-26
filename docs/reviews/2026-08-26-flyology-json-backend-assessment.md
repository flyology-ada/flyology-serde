# Flyology JSON backend assessment

Date: 2026-08-26

Status: gate-only migration checkpoint under change review. This record does not freeze or claim completion of the
event-to-Serde translator described below.

## Reviewed release

This assessment initially covered the indexed `flyology_json=0.1.0-dev` release from source commit
`f8a4a0331a03552733e7bd8531552ba0c21f8997` and Flyology Alire-index commit
`5693988242276f7a93b5034383764f87f5a42890`. Integration consumes the reviewed successor source commit
`3445b7540b89c3d1aa5c55d43b2817fab97710ae` from index commit
`dab710a490366488a1542e82104d531fe9cd25e9`. Relative to the independently accepted parser/API commit
`ae02ae2`, that successor changes only `scripts/verify-release.sh`; the public parser, profiles, and implementation
are byte-identical. The release exposes the trusted incremental `Parsing`
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

The first implemented checkpoint is a syntax-admission gate using one-byte input windows. Before exposing a new
byte, it consumes that byte exactly once from
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
Before this checkpoint freezes, direct tests must record the maximum observed zero-consumption run for complete
one-byte fixtures, malformed fixtures, and every event kind, and exercise the exact ceiling and one-over transition
in the adapter guard without leaving a production test hook. With
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

The event engine remains private behind the existing `Flyology_Serde.Deserializers.JSON.Reader` API. In this
checkpoint the mature handwritten reader remains the sole logical-value, envelope, text, and number translator;
Flyology JSON independently admits every advanced byte and accepts the complete document. This catches syntax drift
without yet satisfying the planned event-to-Reader-state migration. The handwritten reader remains a byte-for-byte
and diagnostic oracle until all JSON, adapter, malformed, arbitrary-bound, budget, abort/reset, and allocation tests
pass against a complete event translator. Root candidate commit still occurs only after
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
precedence, then deliberately discards every diagnostic belonging to that old operation. The statically selected
`Preserve_Unchecked` parser performs no retained-name admission, which is the only current Flyology JSON path that
constructs `Failure_Pending`; Serde therefore cannot manufacture that state without switching to an incompatible
duplicate profile or adding a production test mutation hook. The indexed parser's own lifecycle suite covers that
state. Serde directly tests reset after its reachable reported `Step_Failed` state and retains the defensive pending
diagnostic cleanup branch. A reported or unreported old parse failure is therefore never a reset blocker and never
leaks into the new operation. Only a new cleanup
mechanism defect or failure while applying the new Flyology JSON `Reset`/`Initialize` and profile may prevent
readiness; because the public `Reset` has no error output, such a failure leaves the Reader poisoned and does not
retroactively mutate a caller's prior `Error_Info`. Reset applies the same explicit profile, installs a fresh
`Decode_Budget`, and publishes Reader readiness only after every new-operation step succeeds. Direct tests reset
after a reported `Step_Failed`, then require readiness, a fresh budget, byte offset zero, and no stale diagnostic
leakage. JSON cleanup is nonraising and allocation-free. An unexpected
adapter programming exception performs the same cleanup and then remains an exception; it is never reported as
malformed input or allowed to replace an already latched input diagnostic.

The transactional writer is not adopted in this parser milestone. Serde's current JSON writer preserves its
established logical envelope bytes and publication behavior. A later writer adapter may use Flyology JSON when a
separate change proves byte-for-byte compatibility, destination charging ownership, preflight behavior, and
abort/finalization precedence.

## Decision

- Keep CBOR unchanged and keep the current JSON reader as the conformance oracle during the parser migration.
- After explicit dependency authorization, add exactly `flyology_json = "0.1.0-dev"` from the Flyology Alire index;
  do not add a Git/path pin or a generator dependency. Because the development index entry can advance, require
  every resolved root and test lock to name reviewed source commit `3445b7540b89c3d1aa5c55d43b2817fab97710ae`;
  also require the exact normalized release-metadata block SHA-256
  `a11cf63220d0244a65efd72d94c25adb09ba9443e5494d51d8487890abca2a3f` and the closed reviewed solution-state set.
  An index update therefore fails closed until its exact successor receives another review.
- Freeze the one-byte syntax gate only after its own lifecycle, charge, terminal-diagnostic, and transcript review;
  do not describe that checkpoint as the complete event adapter.
- Implement event-to-existing-Reader-state translation privately before selecting a batched path or deleting
  handwritten parsing code.
- Preserve all current public JSON/CBOR APIs, logical bytes, diagnostics, offsets, budget outcomes, and fixtures.
- Keep this runtime work independent of Ada Type IR, generator attestation, Wire, Flyology tasking, and remoting.

## Review gate

Architecture review must confirm the one-byte admission proof, bounded zero-progress transitions, event/fragment
lifetime, static duplicate/profile selection, exact offset mapping, candidate nonpublication, and reset/abort
precedence. The change review must compare the complete existing JSON suite under both engines, including failed
output preservation, and add direct one-byte charge and zero-progress traces. Any dependency or adapter
implementation still requires explicit dependency authorization and its own final change review.

For the current static `Preserve_Unchecked` instance, direct construction of `Failure_Pending` is non-applicable and
is not a Serde checkpoint gate; the dependency's reviewed strict-instance suite owns that state. A future parser
profile or implementation that makes it reachable reopens this lifecycle test gate before integration.
