# Flyology JSON event scalar reader proposal

Date: 2026-08-26

Status: accepted private root-scalar milestone after architecture, change, and
fix re-review. This narrows, and does not complete,
`2026-08-26-flyology-json-event-reader-proposal.md`.

Historical package-name note (2026-08-27): the reviewed private child named
below became the private sibling
`Flyology_Serde.Deserializers.JSON_Event_Readers` at the public-reader cutover.
The earlier name remains in this record only to describe the reviewed slice.

## Boundary

Add the private child `Flyology_Serde.Deserializers.JSON.Event_Readers`. Its
limited `Reader` implements `Deserialization.Deserializer`, but only root null,
Boolean, signed integer, unsigned integer, binary64, text, `Peek_Kind`, and the
root lifecycle are supported in this slice. No public factory, engine selector,
or public type can construct it. The only construction seam is the sibling
private test package `Deserializers.JSON.Testing`.

`Capabilities` describes the frozen JSON format, not implementation
completeness. It is callable only through that private seam and is not a
general-backend advertisement. `Read_Bytes`, `Skip_Value`, enumeration, and
every optional, sequence, map, record, and variant primitive are concrete
fail-closed stubs. A stub first assigns the same deterministic `out` defaults
as the public reader. A prelatched error then returns without changing reader
state. Otherwise it latches `Invalid_State` at `Reader_Cursor` without source
inspection, parser call, budget debit, boundary claim, cursor movement, or
other output publication. Reset is required after that failure.

This slice cannot satisfy the full event-reader parity, public-selection, or
handwritten-scanner removal gates. Tests claim only private root-scalar parity.
The public JSON reader remains the sole supported backend and conformance
oracle.

## Initialization and ownership

Private `Initialize` and `Reset` take an `Error_Info`; no half-initialized
reader is returned as ready. A prelatched `Initialize` or `Reset` is a strict
no-op for parser, budget, source, cursor, and lifecycle state. Callers reset
the error explicitly before recovery. `Initialize` with no error is legal only
in `Uninitialized`; another state latches `Invalid_State` without cleaning the
old operation. `Reset` with no error is legal in every state. It cleans the old
operation first and publishes `Ready` only when the complete new operation is
constructed; failure leaves the reader failed and publishes no usable budget
or provisional boundary. Initialization applies the fixed strict profile,
creates the one reader-owned `Decode_Budget`, obtains exactly one provisional
zero-source `Document_Begin`, and publishes `Ready` only after all steps
succeed. The driver never owns, creates, resets, or independently charges a
budget.

Reset first aborts and discards the old parser, provisional event, retained
window, deferred follower, candidate, and diagnostic state without refund.
It then creates the new parser operation and budget transactionally. Abort is
legal in every state, including `Ready` and `Complete`; it is nonraising,
idempotent, ledger-free, preserves an earlier diagnostic, and leaves `Failed`.
Unexpected exceptions invoke nonraising abort, clear private candidates, and
re-raise the original exception.

The reader keeps two positions:

- `Reader_Cursor` is the public oracle-equivalent committed source offset;
- the driver's input offset is parser consumption and is never returned as the
  reader offset.

On successful operations they agree. A parser-rejected follower may leave the
driver one admitted byte ahead while `Reader_Cursor` stays at the oracle
failure point. Only that documented input charge may differ from the oracle;
logical values, depth, items, text/byte checks, error offset, and public cursor
must match.

## Root state and terminal ownership

The closed state machine is:

| State | Meaning | Legal next operations |
| --- | --- | --- |
| `Uninitialized` | No usable parser/budget operation | successful `Initialize` or `Reset`; abort |
| `Ready` | One provisional `Document_Begin`; no root value | supported scalar read; `Peek_Kind`; abort; reset |
| `Root_In_Progress` | Logical value charged; transcript unpublished | only the active scalar operation; abnormal abort; reset after failure |
| `Root_Complete` | Scalar transcript complete; no retained delimiter | finish; abort; reset |
| `Root_Complete_Retained` | Scalar terminal event observed with one uncharged legal delimiter window | finish; abort; reset |
| `Root_Complete_Deferred` | Scalar provisionally returned before its terminal event because an invalid follower was not offered | finish; abort; reset |
| `Root_Complete_Unclassified` | Literal/text terminal was not observed because the physical follower lay outside the scalar call's exhausted inspection allowance | finish; abort; reset |
| `Complete` | `Document_End` and `Document_Complete` accepted at physical EOF | idempotent finish; observation; abort; reset |
| `Failed` | Primary diagnostic latched or operation aborted | idempotent abort or successful reset |

Every other traversal call is protocol misuse and follows the fail-closed stub
rule. In particular, another scalar or unsupported call in a deferred state
does not offer or resolve the follower. Direct scalar or text output may
already hold the provisional value, matching the public reader; generated root adapters
retain their Ada candidate privately and cannot commit it until
`Finish_Document` succeeds.

`Document_End` can arrive as a zero-consumption event before the first trailing
whitespace byte is consumed. The reader retains one `Document_End_Seen` flag,
then replays the exact same driver window only when it is whitespace. It
charges and consumes each real trailing whitespace byte once at the public
reader's commit point. An uncharged comma, right bracket, right brace, deferred
invalid follower, or other non-whitespace root suffix is rejected as
`Syntax_Error` at `Reader_Cursor` without parser replay or input charge, then
the parser operation is aborted. A duplicate
or missing `Document_End`, any value event after it, a second offer of one
window, or a zero-progress excess is `Invalid_State`. Completion is published
only after physical EOF, the terminal `Document_Complete`, equal successful
frontiers, no boundary/window/deferred state, and a balanced root.

## Ordered scalar operations

Every supported scalar call uses the public reader's order:

1. assign deterministic `out` defaults and preserve a prelatched error;
2. require `Ready` without touching the parser or ledger;
3. parser-validate and commit leading strict JSON whitespace one byte at a
   time while `Document_Begin` remains provisional;
4. inspect only the uncharged leading byte for the allowed logical kind;
5. consume one logical-value unit;
6. run the bounded raw preflight and destination/policy checks;
7. claim exactly one `Document_Begin`;
8. admit the preflight-owned bytes one at a time and validate the exact event
   transcript;
9. perform checked conversion or complete decoded-text copying; and
10. publish `Root_Complete` or a documented scalar follower state.

Preflight performs no parser call, copy publication, budget charge, cursor
change, or event acceptance. Full physical/syntax checks precede capacity when
the public oracle does so. Leading whitespace is committed before logical
value charging. Token bytes are charged only before parser admission.

`Peek_Kind` preserves the oracle's asymmetric behavior. It commits leading
whitespace and checks call order. It classifies null, Boolean, text, array, and
object from only their leading byte, so malformed `truX` is still Boolean and
an unterminated string is still text. It runs only the number preflight needed
to distinguish signed, unsigned, and float. It never claims
`Document_Begin`, consumes a logical value, admits a token byte, or caches a
token result. A prelatched call returns `Null_Value` and changes no parser,
budget, cursor, lifecycle, or boundary state.

## Transcripts and scalar staging

The accepted complete transcripts are exactly:

```text
null    = Null_Value
boolean = Boolean_Value
text    = String_Begin String_Fragment* String_End
number  = Number_Begin Number_Fragment+ Number_End
```

The retained `Document_Begin` precedes each sequence. A direct root scalar may
return with only its terminal event deferred when an invalid non-delimiter
suffix has not been offered or when a physical follower lies outside the
scalar call's inspection allowance; this provisional return cannot commit an adapter
candidate. Every fragment is copied
before the next driver step. No event, parser range, source-derived access
value, callback, or fragment survives the call that produced it. An event
kind/order/payload mismatch, decoded-length disagreement, unresolved range, or
extra event is `Invalid_State` and publishes no successful root.
String fragment source ranges must also cover every raw token octet between
the opening and closing quote exactly once, in order and without a gap or
overlap; decoded-length parity alone is insufficient.

Literal comparison uses `JSON_Preflights.Match_Literal`. Integer and float
preflights use `Scan_Number`. Signed and unsigned candidates are limited to 32
octets before any token admission and use exact `Flyology_JSON.Numbers`
checked conversion instantiated for `Interfaces.Integer_64` and
`Interfaces.Unsigned_64`. Fraction/exponent requested as integer maps to
`Unexpected_Kind`; signed range and every negative unsigned spelling,
including `-0`, map to `Out_Of_Range`. Binary64 retains the oracle's fixed
768-octet candidate, Ada checked conversion, finite-only rejection, signed
zero, and default-on-failure behavior.

Text preflight establishes raw and decoded lengths, the policy text bound, and
caller capacity before admission. Decoded fragments copy immediately into the
caller array only after checked cumulative arithmetic. Every normal failure
clears the complete array to spaces and returns length zero. A complete
transcript must produce exactly the preflight decoded length. Dynamic staging
is forbidden; candidates are fixed local storage or the already bounded caller
array. `Storage_Error` and unexpected `Constraint_Error` use the abnormal
abort-and-reraise path and can never become malformed-input statuses.

## Scalar-token completion

After preflight owns a complete literal, string, or number token:

- physical EOF uses final input and requires the matching terminal event;
- a real strict delimiter (space, horizontal tab, CR, LF, comma, right bracket,
  or right brace) is offered uncharged solely to obtain the matching
  zero-consumption `Null_Value`, `Boolean_Value`, `String_End`, or `Number_End`,
  then retained unchanged for `Finish_Document`;
- any other follower is not inspected by the parser in the scalar call. The
  provisional value may return and state becomes `Root_Complete_Deferred`.
- when a literal or string consumes the complete remaining inspection
  allowance but physical source continues, the follower is not inspected or
  classified and state becomes `Root_Complete_Unclassified`. No terminal
  selector or payload is retained because the immutable input budget is then
  zero and Finish cannot legally reach another parser event.

Only `Finish_Document` examines a retained or deferred follower in this
scalar-only slice, after its normal prelatched and root-state gates. If it is
strict JSON whitespace, Finish charges and replays it exactly once. Every other
root suffix is rejected as `Syntax_Error` without admission, even when the
input budget is exhausted; this preserves the public oracle's precedence for
`1,`, `1x`, `nullx`, and text followed by junk. Abort and Reset discard
retained/deferred state without admission or refund. A prelatched Finish is a
strict no-op. Finish before a root or after `Failed` latches `Invalid_State`;
repeated Finish after `Complete` is idempotent and ledger-free.

For `Root_Complete_Unclassified`, Finish performs the oracle's ordinary
source-bound lookahead. Non-whitespace is `Syntax_Error` without charge.
Whitespace attempts its one input charge and deterministically fails with
`Capacity_Exceeded`, because entry into this state proves that the immutable
input allowance is already exhausted. No parser call or terminal event is
reachable from this state. Boolean payload validation is instead required at
physical EOF and for every legal retained delimiter, where the terminal event
is observable.

## Required implementation evidence

Before this slice freezes, differential tests compare the private reader and
public oracle after scalar read and finish for values, deterministic outputs,
errors and paths, exact byte offsets, public cursor, completion, and every
budget counter. Matrices cover:

- each supported scalar and exact transcript order;
- signed/unsigned extrema, overflow, `-0`, fractions/exponents, binary64
  signed zero, subnormal and range failure;
- null, Boolean, string, and number terminal events at EOF and all seven legal
  delimiters, plus representative invalid alphabetic/punctuation/UTF-8
  followers, retained-window capacity denial, deferred finish failure, exact
  summary kind/Boolean payload, provisional direct output with root-candidate
  suppression, protocol misuse, abort, and reset;
- text raw UTF-8, every escape class, surrogate pairs, malformed/truncated
  forms, exact/undersized/null/arbitrary-bound outputs, text-policy limits,
  leading whitespace, and a source ending at `Positive'Last`;
- every unsupported abstract method's defaults, prelatched no-op, zero parser,
  budget, and cursor effects, poisoning, and reset recovery;
- denial immediately before every leading-whitespace, token, retained trailing-
  whitespace, and later trailing-whitespace admission, plus logical-value
  denial after committed leading whitespace; `1,`, `1x`, `nullx`, and text
  followed by junk prove `Syntax_Error` wins without another input charge;
- exact-token input limits for `null `, `true `, `false `, and `"x" ` prove
  scalar success followed by Finish `Capacity_Exceeded` before whitespace
  parser inspection; the same limits with non-whitespace suffixes prove Finish
  `Syntax_Error` without another input charge;
- one injected normal transcript mismatch after at least one decoded
  `String_Fragment` copy, proving the entire arbitrary-bound output is cleared
  and length is zero, plus separate gap and overlap source-range mutations;
- initialization, prime, step, scalar-terminal observation, final input, reset, abort,
  zero-progress, and injected-exception cleanup; and
- prelatched Initialize; Reset after reported and unreported failures and every
  retained/deferred/window state; Finish before root, repeated after Complete,
  prelatched, and after Failed; Abort with and without a primary; and old-
  diagnostic discard during successful Reset; and
- wrong expected terminal, duplicate observation, wrong event or Boolean
  payload, nonzero consumption, and observation exceptions before/after Step,
  with default summary, cleanup, primary precedence, and Reset recovery; and
- EOF and retained-delimiter `true` and `false` payload-mismatch mutations,
  requiring `Invalid_State` and no root-candidate commit, plus exact-budget
  unclassified suffix tests proving the closed syntax/capacity precedence; and
- a real root adapter candidate that never commits after deferred-follower
  `Finish_Document` failure.

The full suite, test-hook-elision check, dependency attestation, and forbidden
dependency/ALI scan remain mandatory. This slice changes no public API,
writer, CBOR, Type IR, Wire, or generator surface.

## Review and verification

The first independent change reviews reported P0 none. Their P1 findings
required abnormal reader cleanup, exact number transcript coverage, the
complete scalar conformance matrix, and removal of an unreachable delayed
terminal selector/payload. Their P2 findings strengthened literal, text, and
document provenance, explicit zero-decoded-fragment handling, hook isolation,
and direct lifecycle evidence. The final raw-source fix added a contiguous
frontier and gap/overlap mutations for string fragments. Both final live-diff
re-reviews report P0 none, P1 none, and P2 none.

The accepted tree passes `alr build`, `alr -C tests run`,
`scripts/check-test-hook-elision.sh`, both Flyology JSON dependency-lock
checkers, the 110-column Ada scan, and `git diff --check`.
