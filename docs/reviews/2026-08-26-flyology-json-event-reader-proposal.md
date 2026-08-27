# Flyology JSON event reader proposal

Date: 2026-08-26

Status: pre-implementation architecture proposal. The committed syntax gate remains authoritative until this
proposal and its implementation pass separate P0/P1/P2 reviews.

## Scope

Add a private `Flyology_Serde.Deserializers.JSON.Event_Readers` implementation of the existing bounded
`Deserialization.Deserializer` interface. It consumes the reviewed `Flyology_JSON.Parsing` event grammar and lowers
Serde's established JSON envelopes. It does not change the public `Deserializers.JSON.Reader`, the writer, CBOR,
Type IR, Wire, or any logical adapter contract in this milestone.

The current public Reader remains the conformance oracle. Tests run the same root adapters and direct fixtures
against both readers and compare values, output clearing, error codes, zero-based byte offsets, completion, and every
budget counter at each operation boundary. Only a later reviewed change may replace the public Reader and remove
the handwritten value scanner. There is no runtime engine-selection flag and no production authority is granted to
the parallel reader.

## Raw preflight and event authority

An event-only lowering cannot preserve the public Reader's existing denial points. The oracle validates a complete
string, name, number, or byte payload and its destination capacity before admitting any part of that token. The
parallel reader therefore retains a deliberately narrow raw preflight layer. Existing scanners move into a private
`JSON_Preflights` child and become nonmutating observations over the immutable caller-borrowed source.

A preflight:

- starts only when there is no parser window or provisional token/fragment event; the retained zero-source
  `Document_Begin` is the sole exception and remains unclaimed until the preflight succeeds;
- starts at `Reader_Cursor`, which equals `Admission_Frontier` at every public operation entry;
- uses relative `Natural` counts and validates every conversion before adding a count to `Source'First`;
- cannot inspect beyond the existing `Input_Remaining` bound;
- makes no parser call, budget debit, cursor change, acceptance decision, or output publication;
- computes only raw token extent, decoded length, numeric sign/kind, and the oracle's exact failure offset; and
- is at most linear in the inspected token or remaining container fragment and performs no allocation.

Text, name, number-candidate, and byte-output capacity are checked after this preflight and before event collection,
at the same point as the oracle. The Flyology JSON transcript remains the final syntax and Unicode authority. A
successful preflight never permits final document or root-candidate acceptance without the matching complete event
transcript. A root scalar whose final zero-consumption event requires a later
parser step may return a provisional value before that event when the next
source byte is an invalid non-delimiter or is outside the scalar call's
remaining inspection allowance. This applies to literal, string, and number
terminals and matches the existing pull API's trailing-suffix timing. The
return is not parser-complete token acceptance. `Finish_Document` rejects the
uncharged non-whitespace suffix at the public reader's cursor and can never
publish the adapter candidate until the complete token/document transcript
exists. Any other disagreement is an internal `Invalid_State`, aborts the
parser, and publishes no result.

`Peek_Kind` uses the same bounded preflights and does not call `Step`, debit a budget, move a frontier, or cache an
accepted token. This is the existing nonmutating public convention. Repeated calls by a trusted caller may repeat
bounded work; generated adapters invoke it only at bounded protocol points. One call is bounded by
`Input_Remaining`, so adversarial input cannot create unbounded work inside a call.

## Private event boundary

The existing private JSON driver is extended into one event source shared by the syntax gate and parallel reader.
It retains one copied input byte at a time, freezes the exact strict profile already committed, and never exposes a
Flyology JSON `Event`, raw range, parser, access value, or borrowed slice. Its observation operations return only
fixed event-kind/Boolean summaries or synchronously copy a complete decoded name, decoded string, or exact number
lexeme into caller storage.

The generalized boundary operation is
`Observe_Token_End (Self, Expected, Summary, Error)`. `Expected` has a closed
private selector type with exactly `Null_Terminal`, `Boolean_Terminal`,
`String_Terminal`, and `Number_Terminal`; callers cannot request another event
kind. A prelatched call sets `Summary` to its default and is a strict no-op.
Otherwise the driver requires an initialized, nonfailed operation with no
pending document boundary or retained window, a current source byte, and that
byte equal to one real strict delimiter. It copies that exact byte into its
one-byte window without charging it, performs exactly one nonfinal parser
`Step`, and accepts only the selector's matching `Null_Value`,
`Boolean_Value`, `String_End`, or `Number_End` with zero consumption. The
copied summary is published only after all checks pass; the Boolean payload is
then checked by the reader against its preflighted literal. The exact delimiter
byte remains unchanged, retained, and uncharged for later replay. A wrong
event, consumption, parser outcome, range, or lifecycle state aborts and
poisons the driver as `Invalid_State`, publishes the default summary, and
retains no usable token. Unexpected exceptions take the existing nonraising
abort-and-reraise path. The existing number-only observation entry point is a
temporary wrapper around this operation until all callers migrate.

Raw or decoded fragments are observed only before the next `Step`. A raw range must resolve into the exact retained
one-byte producing window; an inline scalar is copied from the event value. Failure to resolve the documented range
is `Invalid_State`, aborts the parser, and publishes no token. Complete text/name and number collection is
transactional for every normal return: checked cumulative arithmetic precedes copying, and a detected failure clears
the caller output before returning. Abnormal transfer is governed by the narrower rule in the lifecycle section.

The driver tracks three monotonic zero-based frontiers:

- `Admission_Frontier` is the byte count already charged to the one Serde `Decode_Budget` as consumable parser
  input. A rejected consumable byte can remain charged even though neither parser nor pull cursor commits it.
- `Parser_Offset` is Flyology JSON's consumed-byte count.
- `Reader_Cursor` is the byte count committed by the pull protocol and exposed through `Input_Offset`.

Every pull call owns a closed raw byte interval `[Call_Start, Owned_End)`, computed by its preflight. The parser is
never offered a consumable source byte outside that interval. Token completion
has four closed cases after raw preflight establishes the complete literal,
string, or number spelling. At physical source end, the driver offers an empty
window with `End_Of_Input = True` and requires the matching terminal event.
When the following source byte is a strict JSON token delimiter
(space, horizontal tab, CR, LF, comma, right bracket, or right brace), preflight has already proven that byte within
`Input_Remaining`; the driver copies that exact byte into its private one-byte
window without charging it and calls `Step` solely to obtain the matching
`Null_Value`, `Boolean_Value`, `String_End`, or `Number_End`. Flyology JSON
specifies zero consumption for this case.

For a literal or string, the physical source can continue while the complete
token consumes the call's entire `Input_Remaining` allowance. The scalar call
cannot inspect or classify that follower. It records the expected terminal
state in `Root_Complete_Unclassified`, with no selector, payload, window, or
follower-derived state, and may return the provisional value. At root
`Finish_Document`, ordinary source-bound lookahead preserves the public oracle:
an uncharged non-whitespace suffix is `Syntax_Error` at `Reader_Cursor`; a
whitespace suffix attempts its one input charge and deterministically returns
`Capacity_Exceeded`, because entry proves the immutable input allowance is
zero. No parser step or terminal payload is reachable in this state. Boolean
payload is validated at physical EOF and every legal retained delimiter,
where the event is observable. Abort and Reset discard the unclassified state
without charge or refund. Number preflight already requires follower lookahead
whenever a physical follower exists, so a number never enters this fourth
state.

Any other follower is oracle-invalid trailing syntax, not a JSON token
delimiter. The scalar read does not offer it to the parser. It records a
deferred terminal event with no window and may return the preflighted scalar or
text, matching the public Reader's timing. `Finish_Document` rejects that exact
uncharged byte as `Syntax_Error` without parser admission. No later scalar or
document can complete, and the private adapter candidate remains unpublished
and is aborted. A protocol-misuse call and `Abort_Document` do not resolve
deferred completion.

The legal-delimiter unconsumed window is retained unchanged after the scalar
terminal event; it is the one exception to an otherwise empty driver
window at a successful public return. The next operation must re-present that exact byte as the first byte of the
same unconsumed suffix. Immediately before the parser may consume it, the driver charges it once, changes the window
to admitted, and never copies or charges it again. An operation such as close lookahead may leave it uncharged and
retained across one more public return; the matching `End_*` then charges and consumes it. Abort/Reset discards either
window state and deferred terminal event without charge or refund. No other
lookahead or event may retain an uncharged
window.

Within an operation, a byte can be in exactly one state:

1. unadmitted at or after `Admission_Frontier`;
2. charged and retained as the parser's sole unconsumed window byte;
3. parser-consumed but not yet pull-committed within the call-owned interval; or
4. pull-committed after the parser has consumed the same byte.

`Parser_Offset` and `Reader_Cursor` never exceed `Admission_Frontier`. Admission charges a consumable byte exactly
once before copying it into the parser window. Pull commit moves `Reader_Cursor` only at the oracle's corresponding
`Advance` point and only after the parser has consumed and validated that byte. There is no parser catch-up across a
public operation boundary and no generic `max` rule. Every successful public return has
`Parser_Offset = Admission_Frontier = Reader_Cursor`. Equality does not count the optional uncharged scalar-terminal
window, because that byte belongs to the unconsumed suffix. On failure, admission may lead the other frontiers only
by one admitted failing source byte, whether consumed or retained by the parser. That byte remains charged and is
never refunded.

Container close lookahead reads only the byte at `Reader_Cursor`, after checked arbitrary-bound translation and under
`Input_Remaining`. It neither admits nor debits the byte. The matching `End_*` call owns and commits it at the oracle's
existing point. Lookahead selects a pull-protocol branch; it cannot decode a value, publish a candidate, bypass the
complete-document gate, or accept syntax rejected by the event transcript.

## Closed event grammar

The lowering accepts only these balanced transcripts, where fragments are immediate-lifetime observations and
commas/colons are represented by parser state transitions rather than public events:

```text
document-events = Document_Begin value Document_End
name           = Name_Begin Name_Fragment* Name_End
string         = String_Begin String_Fragment* String_End
number         = Number_Begin Number_Fragment+ Number_End
record         = Object_Begin (name value)* Object_End
sequence       = Array_Begin value* Array_End
map            = Array_Begin (Array_Begin value value Array_End)* Array_End
optional-none  = Array_Begin number("0") Array_End
optional-some  = Array_Begin number("1") value Array_End
bytes          = Object_Begin name("$bytes") string(raw-even-hex) Object_End
variant        = Array_Begin string(alternative) Object_Begin (name value)* Object_End Array_End
```

After `Document_End`, one further `Step` must return the terminal outcome `Document_Complete`; it is not an event.
After successful profile initialization, the driver makes exactly one empty, nonfinal `Step` and requires the single
zero-source `Document_Begin` with zero consumption. It retains that provisional boundary without touching a budget or
byte frontier. The first value-reading operation claims it only after its call-order, leading-kind, logical-budget,
and raw-preflight gates succeed, before accepting the value-begin event. This permits leading whitespace to be
parser-validated without reordering the oracle's gates. A missing, duplicate, or wrong boundary is `Invalid_State`.
`Finish_Document` owns the zero-source `Document_End` and the following terminal outcome. Neither boundary changes a
byte frontier or input budget.

The bytes object has exactly one member. Its payload source bytes must be unescaped ASCII hexadecimal digits, accept
the same upper- and lower-case digits as the oracle, and have even length. A decoded fragment can never legitimize an
escape in this envelope. The optional has exactly zero or one child. A map entry has exactly two elements. A variant
has exactly two top-level elements and its payload is exactly one object. Extra or missing children are rejected at
the oracle's punctuation offset.

Container lengths remain unknown. Serde retains duplicate and alias policy because the parser is statically
`Preserve_Unchecked` and publishes every name in source order. Comments and trailing commas remain disabled by the
frozen `No_Extensions` profile. Event-free trivia in other Flyology JSON profiles therefore cannot affect this
reader, and no compatibility-family authority leaks into Serde.

## Operation ordering and accounting

The private reader owns the same logical root/container state machine and the same single `Decode_Budget` as the
public Reader. It does not replace the oracle's order with a uniform "logical charges first" rule. Each operation
uses this exact sequence; an earlier failure prevents every later action.

| Operation | Ordered actions |
| --- | --- |
| Null/Boolean | `Require_Leading`: call order, commit whitespace, inspect leading byte; logical value; full literal comparison without admission; event transcript and raw commit; finish value |
| Signed/Unsigned/Float | `Require_Leading`: call order, commit whitespace, inspect leading byte; logical value; number preflight and candidate capacity; event transcript and raw commit; checked conversion; finish value |
| Text/Enumeration | `Require_Leading`: call order, commit whitespace, inspect leading byte; logical value; string preflight, text limit, and destination capacity; event transcript and raw commit/copy; finish value |
| Bytes | call-order and leading check; logical value; admit object/name/colon/opening quote; raw hex preflight, byte limit, and destination capacity; transcript/copy; admit closing quote/object; finish value |
| Begin sequence/map/record | `Require_Leading`; logical value; admit opener; enter budget depth; check local depth; publish protocol frame |
| Begin optional | `Require_Leading`; logical value; admit array/tag; validate exact zero/one cardinality; admit child separator/start when present; enter budget depth; check local depth; publish frame; charge one container item only for `some` |
| Next element | frame state; whitespace/close lookahead; comma when nonfirst; child-start check; charge one container item; publish child-ready state |
| Next map entry | frame state; whitespace/close lookahead; comma when nonfirst; admit entry array; child-start check; charge one outer item; publish key-ready state |
| Map key finish | finish key value; admit comma; require value start; publish value-ready state |
| Map value finish | finish value; admit entry close; publish entry-finished state |
| Next record/variant field | frame state; whitespace/close lookahead; comma when nonfirst; name preflight and transcript; admit colon; child-start check; charge one container item; publish field-ready state |
| End container | frame/exhaustion check; admit exact closer(s); pop frame; leave depth; finish containing value |
| Begin variant | `Require_Leading`; logical value; admit array; alternative preflight/transcript; admit comma/object; enter budget depth; check local depth; publish frame |

`Require_Leading` is a named oracle-equivalent sequence, not one indivisible action. It first preserves a prelatched
error, then validates call order, commits leading whitespace, and finally inspects the uncharged leading byte for the
allowed kind. `Expect_Literal` likewise performs a complete length/content comparison before admitting any literal
byte; malformed `truX` therefore consumes and charges nothing beyond earlier whitespace in both readers.

`Skip_Value` charges one logical value, then balances one generic JSON value transcript. Its raw preflight preserves the
oracle's whitespace, text, raw syntax-depth, and raw-container-item checks. Representation objects, arrays, names,
and envelope fragments do not create additional logical values, Serde container items, or Serde depth entries. Each
raw nested container increments only the existing syntax-depth counter and applies the existing per-container raw
item bound. The complete skipped interval is event-validated before the pull cursor commits it.

Preflight is noncharging. Event collection charges each newly admitted input byte exactly once. Logical values,
container items, text/byte lengths, depth, and work retain their present owner and present order. A parser rejection
after admitting a byte consumes that input charge even when the oracle would reject the raw character without moving
its cursor; this is the one intentional internal-accounting distinction. Public error offset and cursor remain at the
oracle point, and parity tests compare all logical/depth/item/text/byte counters while permitting only this documented
input-unit retention on a rejected parser byte. Successful operations and completed documents must have identical
budget totals across engines.

## Scalars and status mapping

Exact integer candidates use the Flyology JSON checked signed/unsigned conversion packages. Binary64 retains the
current fixed 768-byte candidate and checked Ada conversion until Flyology JSON publishes a separately reviewed
binary64 conversion API. Conversion never changes the profile or number lexeme and preserves signed zero, range
statuses, and scalar defaults on failure.

The mapping is closed and the first applicable result wins:

1. a prelatched error preserves its original code and offset and is a strict no-op for parser, budget, cursor, and
   reader protocol state; each operation still assigns the same default `out` values as the oracle before returning;
2. new caller protocol misuse: `Invalid_State`, with no parser call;
3. valid JSON value of the wrong logical surface kind: `Unexpected_Kind` at the value start;
4. fractional/exponent number requested as integer: `Unexpected_Kind` at the number start;
5. negative unsigned or checked numeric range failure: `Out_Of_Range` at the number start;
6. wrong `$bytes` tag or another semantically wrong envelope kind: `Unexpected_Kind` at the oracle point;
7. invalid optional discriminator, missing/extra envelope member or child, bad separator/closer, invalid escape,
   raw string control, or non-hex/odd byte payload: `Syntax_Error` at the oracle point;
8. invalid UTF-8 or invalid surrogate structure: `Invalid_Text` at the exact offending byte;
9. other Flyology JSON lexical/grammar failure: `Syntax_Error` at its exact byte offset;
10. Flyology JSON depth exhaustion: `Depth_Exceeded`; offset exhaustion or local arithmetic overflow:
    `Capacity_Exceeded`;
11. Serde resource denial or destination shortage: the oracle's existing `Capacity_Exceeded` or `Out_Of_Range`; and
12. impossible transcript, preflight disagreement, stale fragment, profile mismatch, or parser call rejection:
    `Invalid_State`.

A Flyology JSON terminal diagnostic is copied once and never replaces an earlier Serde diagnostic. Output clearing
matches the oracle: text/name/bytes/candidate buffers publish only after the whole operation succeeds and are empty
or zero on every non-success.

## Failure, abort, reset, and abandonment

A parser `Step_Failed` first records its positive consumed count in `Parser_Offset`, then copies the primary
diagnostic. `Reader_Cursor` moves only to the oracle's failure point. A prelatched error performs no parser call.
Unexpected programming exceptions abort parser/token candidates, unwind every entered Serde budget scope while
preserving the primary diagnostic, and re-raise.

`Abort_Document` is nonraising and idempotent. It never calls `Step`, never catches the parser up, and never debits a
budget. It may copy only an already-retained terminal diagnostic when no primary exists, then invokes the parser's
nonraising `Abort_Document` and discards all token/protocol state. `Reset` performs that same abort/discard, drops the prior
diagnostic, applies the exact frozen profile, initializes one fresh budget, resets all frontiers, and publishes
readiness only after initialization succeeds. Cleanup failure cannot replace a primary error.

The limited reader retains its existing immutable source access discriminant for the reader lifetime. No parser
fragment, callback, token candidate, or additional input access escapes an operation, and parser/token/budget state
is allocation-free. Abandoning a reader therefore requires no finalization action: normal scope reclamation releases
the source borrow and drops private state without an escaped callback or resource. Explicit `Abort_Document` is
required only for deterministic reuse and diagnostic lifecycle.

Normal failure returns clear caller arrays and lengths exactly as the oracle does. Asynchronous task abort or another
abnormal transfer during a by-reference output copy can leave that output actual unspecified; it must propagate out
of the adapter, and the private deserialization candidate and reader must be discarded rather than committed, reset,
or reused. This boundary claims no abort-deferred output transaction. Tests cover ordinary injected exceptions and
abandoned scopes; a task-abort copy test is required only if a later change adds an abort-deferred guarantee.

`Finish_Document` requires balanced Serde state, exact `Document_End`, Flyology JSON `Document_Complete`, equal
frontiers at complete source length, and no pending token/event before publishing completion.

## Work and arbitrary bounds

One preflight scans each owned interval at most once. Event collection processes each owned source byte once and emits
at most the Flyology JSON grammar's fixed zero-consumption boundary events plus one fragment event per admitted byte.
Each scalar token whose terminal event needs a legal delimiter offers its exact
following byte once for zero-consumption terminal observation and later offers
that retained byte once for actual parser consumption; the second offer is the
same unconsumed suffix, not a rescan or copy. A scalar followed by an invalid
token byte defers completion and root Finish rejects that byte without parser
admission. A scalar at physical source end adds one empty final-input `Step`.
The existing zero-progress guard bounds
boundary events from the closed 17-kind grammar. No operation rescans an already accepted token or performs indexed
child lookup. Thus one pull operation is linear in its owned source span plus at most one constant-cost scalar-terminal
observation; parser `Drain` is outside this milestone.

All source addressing is relative. The implementation validates lengths and converts counts before computing an Ada
index, including sources whose first or last bound is near `Positive'Last`. Public operation entry requires
`Parser_Offset = Admission_Frontier = Reader_Cursor`. Lookahead accepts only a relative cursor and source length,
never an unchecked native index. Tests cover null
and non-1-based arrays, a one-byte source ending at `Positive'Last`, every exact limit boundary, and denial before
each checked addition.

## Review and removal gates

Architecture review must close raw-preflight scope, call-owned intervals, exact-once charging, operation ordering,
pull delimiter timing, immediate fragment lifetime, duplicate policy, scalar conversion, status mapping, work
bounds, and abort/reset precedence before implementation. Change review must include every existing JSON
direct/adapter/allocating fixture against both engines; exact successful budget totals and the documented rejected
input-byte distinction; intermediate delimiter-denial cases; arbitrary-bound source and destination arrays; every
event kind; split Unicode and number fragments; duplicate/alias matrices; malformed and truncated inputs;
depth/item/text/byte/input limits; prelatched errors; abort/reset and abandonment from every reachable state; and
exception cleanup with production hook elision. Scalar-terminal boundary tests
cover null, Boolean, string, and number at physical EOF, every legal whitespace
and structural follower, representative illegal alphabetic/control/UTF-8/
structural followers, exact and one-short input limits, and arbitrary source
bounds. They assert the exact summary kind and Boolean payload, zero legal-
terminator consumption, unchanged frontiers and budget, provisional direct
output but no root-candidate publication, the exact retained byte/offset and
uncharged state, exact same-window replay, exactly-once admission only for real
trailing whitespace, uncharged invalid-follower rejection in root Finish, and
state clearing after later consumption, rejection, or Abort/Reset.

Direct driver conformance also injects wrong `Expected`, duplicate observation
after a terminal was already emitted, wrong terminal kind or Boolean payload,
nonzero consumption, and exceptions before and after `Step`. Every case proves
default summary publication, exact retained-window cleanup, primary
diagnostic/exception precedence, and Reset recovery.

The deferred-unclassified tests mutate delayed `true` and `false` payloads and
require `Invalid_State`, default/no committed candidate, retained primary
precedence, and Reset recovery.

The handwritten reader is removed only in a later focused subtraction change after the event reader is the public
engine, the complete parity matrix is green, and another P0/P1/P2 review finds no oracle-only behavior. Batched
`Drain`, Flyology JSON writing, comment/trailing-comma profiles, and binary64 API adoption each remain separate
decisions.
