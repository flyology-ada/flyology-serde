# Flyology JSON event container foundation proposal

Date: 2026-08-26

Status: accepted architecture; implementation in progress. The sequence,
record, map, and optional slices are reviewed; the remaining container scope
is pending. It extends the accepted private root-scalar milestone and grants
no public backend-selection authority.

## Scope and authority

Extend `Flyology_Serde.Deserializers.JSON.Event_Readers` from root scalars to
the complete existing Serde JSON data model: nested scalars, sequences, maps,
records, optionals, variants, enumerations, byte envelopes, and `Skip_Value`.
The public handwritten reader remains the conformance oracle until one later
reviewed parity change replaces it. Flyology JSON remains the syntax, Unicode,
number-lexeme, event-grammar, and source-offset authority. Serde retains every
logical envelope, candidate, alias/duplicate, budget, path, and adapter policy.

This milestone changes no public traversal interface, writer, CBOR backend,
Type IR, Wire, generator, or format profile. The parser remains the static
`Preserve_Unchecked` and strict `No_Extensions` instantiation already pinned by
the repository. No parser event, range, input access, or fragment can escape
the private reader call that observes it.

## Independent state domains

The root-scalar lifecycle states are replaced by three independent closed
domains. Conflating these domains would either publish a nested child early or
make a retained separator look like a completed document.

Operation state is `Uninitialized`, `Ready`, `Active`, `Complete`, or `Failed`.
It owns initialization, reset, final document acceptance, and poison. Root
state is `Root_Ready`, `Root_In_Progress`, or `Root_Complete`. Each container
frame owns its child or map phase. The fixed stack is bounded by
`Policies.Maximum_Supported_Nesting`; it contains no access value and is
cleared on every normal poison, reset, abort, or abnormal cleanup.

Operation state also owns `Document_End_Seen` and `Root_End_Offset`. The only
retained document-boundary observation across calls is that copied Boolean
plus the validated zero-based offset; no Flyology JSON event or range survives
its producing Step. `Document_End` is accepted only after a root scalar terminal, together
with a root closer in the same driver call, or during final document stepping.
It must be zero-source at `Root_End_Offset`, appears exactly once, is cleared by
failure/abort/reset, and is required before `Document_Complete` can publish
`Complete`.

When a root `Array_End`/`Object_End` and `Document_End` occur in one
`Consume_One` batch, the reader computes a checked local
`Post_Closer_Offset = Cursor + 1`, validates the closer first, validates the
boundary against that local offset, and rejects every extra summary. Only at
the irreversible closer commit cut does it atomically publish
`Root_End_Offset = Post_Closer_Offset` and `Document_End_Seen = True`. Neither
fact survives if the closer or any batch invariant fails.

One separate scalar-terminal state is:

- `No_Pending_Terminal`: no scalar suffix window or deferred follower;
- `Retained_Delimiter`: the driver has emitted the scalar terminal and retains
  exactly one uncharged strict delimiter;
- `Deferred_Invalid_Follower`: the scalar returned provisionally without
  offering an invalid non-delimiter follower; or
- `Unclassified_Exhausted`: a literal/text consumed the complete immutable
  input allowance, so its physical follower was not inspected and no terminal
  selector or payload is retained.

Terminal state is observation, not authority. It never identifies a Serde
type or commits an adapter candidate. It is bound invariantly to the exact
active value slot: root, ordinary child at the current depth/kind, map key or
value phase, or optional representation tag at its candidate/current depth.
No frame can pop or reuse that depth while the binding exists. Every resolver
checks operation state, exact depth/kind/phase, terminal binding, and source
classification before any charge or state/output publication. Clearing the
terminal binding is part of the same transition that consumes its retained
window or poisons/discards the operation. The sole two-stage exception is
uncharged closer lookahead: `Next_Element` or `Next_Field` may atomically
rebind a completed-child terminal to that exact frame's exhausted `End_*`
phase without replay. Only the matching `End_*` may then charge/replay and
clear it; a wrong End owner is protocol misuse.

Variant-alternative strings, record/bytes names, and the bytes payload use
operation-local terminal candidates rather than persistent bindings. Their
`String_End`/`Name_End` may be retained, deferred, or unclassified, but the
same `Begin_Variant`, `Next_Field`, or `Read_Bytes` call must synchronously
resolve the exact comma/colon/closer before returning. The local candidate and
any retained window are discarded on failure; they can never be rebound to a
later public operation. Optional-some uses the same local rule, while optional-
none alone binds its tag terminal to the published optional frame for
`End_Optional`.

The installed Flyology JSON grammar emits `Name_End` while consuming the
closing quote, so the private driver has no `Name_Terminal` selector. The
record reader validates strict whitespace and the colon directly after the
complete name transcript, before either can be admitted. The existing
string/number/literal selectors retain their closed value-delimiter set. This
follower classification remains a private Serde implementation detail and
never enters Flyology JSON or the format-neutral traversal API.

Resolution is context-sensitive. Uncharged source classification comes first.
A delimiter is charged/replayed only when it is whitespace or the valid
separator/closer owned by the current root/frame phase. A comma, right bracket,
or right brace that is invalid at root or for the current parent is
`Syntax_Error` without charge/replay; failure cleanup discards the retained
window. Abort and Reset may also discard it without charge or refund. A
deferred invalid follower can only become uncharged `Syntax_Error` at the
reader cursor. For `Unclassified_Exhausted`, an invalid contextual suffix is
likewise `Syntax_Error`; a valid whitespace/separator/closer reaches its normal
input owner, which deterministically returns `Capacity_Exceeded` because the
allowance is already zero. No parser call occurs after that denial.

## Value ownership

`Check_Value_Ready` accepts exactly one root in `Root_Ready`, one ordinary
container child in `Child_Ready`, or one map key/value in its matching ready
phase. `Prepare_Value` consumes one logical value before parser admission and
changes that exact slot to in-progress. It claims the retained
`Document_Begin` only for the root and only after all operation-specific raw
preflights and destination checks that precede parser admission.

`Finish_Value` is called after the complete value bytes and every event already
available under that operation's inspection allowance have been validated. A
scalar may finish provisionally with `Retained_Delimiter`,
`Deferred_Invalid_Follower`, or `Unclassified_Exhausted`. At root,
`Root_In_Progress` becomes `Root_Complete`; in an ordinary container,
`Child_In_Progress` becomes `No_Child`. The nonempty terminal binding is an
invariant companion to that provisional completion and is resolved only by
the exact next parent/document operation.

A map is stricter: key completion must resolve and consume its comma and prove
the value start before publishing `Map_Value_Ready`; value completion must
resolve and consume the entry-array closer before publishing
`Map_Needs_Entry`. A scalar or nested-container map child therefore never
returns with a provisional map phase. Any retained/deferred/unclassified
terminal is resolved inside that scalar or `End_*` call; failure poisons the
operation and publishes no next phase. `Finish_Value` never publishes an Ada
candidate; the existing root adapter still commits only after
`Finish_Document` accepts `Document_Complete`.

Starting another scalar/value while a retained, deferred, or unclassified
terminal is unresolved is protocol misuse. The exact current-parent traversal,
map transition, optional end, or `Finish_Document` is the only resolver.

## Container frames

The stack keeps the public reader's closed frames:

- optional: zero children or one ready/in-progress child;
- sequence: first-item, child, and exhausted state;
- map: outer first-entry/exhausted state plus key/value/entry phases;
- record: first-field, child, and exhausted state; and
- variant: the same field state after the alternative and object envelope.

Frame/output publication is transactional. The operation constructs a local
candidate frame, enters the caller-owned decode budget with unknown length,
performs any charge required before publication (notably the optional-some
item), checks the fixed local stack ceiling, and only then publishes stack
depth/frame and `out` values together. A denial after budget entry leaves that
scope through the common error-preserving poison path and publishes neither
frame nor output.

`Pop` requires the exact kind, no active child, the required map phase, prior
exhaustion, and a matching terminal binding if one exists. Before every closer
is accepted, failure uses common unwind while the frame is still logically
entered. After all closers and their events validate, the irreversible commit
cut clears the frame, decrements stack depth, and leaves that budget scope
exactly once. It then finishes the containing value. A later parent-transition
failure cannot roll back consumed bytes or the pop; it poisons and unwinds the
whole operation, retains all charges, and publishes no adapter candidate.

Container length remains unknown. `Next_*` returns unavailable only after
uncharged lookahead proves the exact closer. It does not consume that closer;
the matching `End_*` owns its input charge and event. A separator is charged
once at the same public-oracle point. After it, whitespace is charged one byte
at a time before the next child-leading check. A container item is charged
only after syntax establishes a real next child/entry/field and immediately
before publishing the corresponding ready phase.

Optional tag handling is explicit. The exact representation number `0` or `1`
can itself end provisionally. For `1`, `Begin_Optional` must resolve its
terminal, consume the comma/whitespace, prove the child start, enter the budget,
charge the one item, then publish `Present = True` and its frame. For `0`, it
enters the budget and publishes `Present = False` plus a frame whose optional-
tag terminal binding is resolved only by `End_Optional`; `[0]`, `[0 ]`,
`[0,]`, and `[0x]` therefore retain the oracle's end-time syntax/capacity
precedence. The current public reader's partial `Present = True` on item-budget
denial is a bug: this milestone first stages/fixes that reader so every normal
failure returns `False`, then requires exact differential parity.

## Event transcripts

The reader accepts only these balanced physical transcripts:

```text
sequence       = Array_Begin value* Array_End
map            = Array_Begin (Array_Begin value value Array_End)* Array_End
record         = Object_Begin (name value)* Object_End
optional-none  = Array_Begin number("0") Array_End
optional-some  = Array_Begin number("1") value Array_End
variant        = Array_Begin string(alternative)
                 Object_Begin (name value)* Object_End Array_End
bytes          = Object_Begin name("$bytes") string(raw-even-hex) Object_End
```

Commas and colons are event-free parser transitions but still have exact raw
ownership and budget points. Event provenance is closed by kind:

| Event | Required source and payload |
| --- | --- |
| `Document_Begin` | zero-source offset zero, no raw byte |
| `Document_End` | zero-source at exact `Root_End_Offset`, no raw byte, once |
| `Array_Begin`/`Array_End` | length one, exact `[`/`]` raw byte |
| `Object_Begin`/`Object_End` | length one, exact `{`/`}` raw byte |
| `Name_Begin`/`Name_End` | length one, exact quote raw byte |
| `String_Begin`/`String_End` | length one, exact quote raw byte |
| name/string fragment | nonempty next contiguous raw range; immediate decoded payload rules from the installed parser contract |
| `Number_Begin`/`Number_End` | zero-source at exact token frontier, no raw byte |
| number fragment | nonempty next contiguous raw range and exact lexeme octets |
| `Null_Value`/`Boolean_Value` | exact complete literal range and Boolean payload; raw eligibility follows the producing window |

Each name/string Begin, its contiguous interior fragments, and its End cover
the complete quoted token in order without gaps or overlap. Number fragments
cover the exact tag lexeme once. A closing
root container may produce its closer followed by zero-source `Document_End`
in the same one-byte driver step; both summaries are copied and validated in
that call, and only the closed `Document_End_Seen` fact survives for
`Finish_Document`. No other extra event is legal.

The map entry array has exactly two children. Optional tags are exact integer
lexemes `0` or `1` and create zero or one child. A variant has exactly the
alternative text and one object payload. The bytes object has exactly the raw,
unescaped name `$bytes` and one raw, unescaped, even-length hexadecimal string.
Decoded text cannot legitimize an escaped representation name or byte payload.

Enumeration delegates to the same text value transcript but remains a distinct
adapter operation. `Skip_Value` balances exactly one arbitrary JSON value with
a fixed local raw-frame stack, separate from persistent logical frames. Each
raw frame records array/object kind, first/item phase, object name/colon/value
phase, and a checked item count. Its fixed storage has an implementation
ceiling at least as large as every admitted caller limit, but that ceiling is
not a second admission policy. Before each raw opener, read logical
`D = Budgets.Depth`, reject if `D` exceeds the caller's
`Maximum_Nesting_Depth`, compute
`Remaining = Maximum_Nesting_Depth - D` with checked subtraction, and reject
when raw depth equals `Remaining`. Each real array value or object member is
rejected before increment when the per-frame count equals
`Maximum_Container_Items`. Checked relative arithmetic precedes every source
translation. Failure or exception clears the transient stack through the
common poison path. Raw frames do not enter/leave logical budget depth or
consume logical container items; the outer skipped value consumes exactly one
logical value.

There is no `Work_Units` category in `Decode_Budget`, so work is a derived
bound rather than a denial limit. For one `Skip_Value` call that admits `N`
bytes, let `M = Drivers.Maximum_Event_Summaries`. The implementation must keep
noncharging token-preflight/follower/phase classifications at or below
`4 * N + 2`; parser Step attempts at or below `(N + 1) * (M + 1)` including
terminal observation/replay and EOF zero-source steps; copied decoded octets at
or below `4 * M * N`; and raw-frame push/pop/phase operations at or below
`4 * N + 2`. Each byte is admitted and input-charged at most once, but may be
classified before later admission and a retained window may require bounded
zero-consumption Steps before its one replay. All formula arithmetic is
overflow-checked or compared by division before instrumentation. Private test
counters trace every category at empty, exact input/depth/item limits and at
one-past denial. Representation events do not consume extra logical Serde
values, depth, or items.

## Ordering and failures

Each operation preserves the public reader's existing order table in
`2026-08-26-flyology-json-event-reader-proposal.md`. Raw preflight is
noncharging and cannot claim events. Every admitted source byte is charged
exactly once before copying it into the parser window. Logical values, depth,
container items, text/byte length checks, and caller capacity retain their
current owner and denial point.

A wrong event kind/order/source/payload, duplicate or missing boundary,
zero-progress excess, foreign retained window, or reader/driver frontier
disagreement is internal `Invalid_State`; it aborts and poisons the operation.
Malformed source remains `Syntax_Error`, type mismatch remains
`Unexpected_Kind`, bounds use the existing capacity/depth/out-of-range codes,
and a prelatched error is a strict no-op after deterministic `out` defaults.

Every newly latched normal status uses one common nonraising poison path. It
preserves the primary diagnostic; asks the driver to preserve any unreported
parser diagnostic only when no primary exists; aborts parser state; calls
`Leave_Container` exactly once for every entered budget scope until depth zero;
clears every logical/raw frame, terminal binding, document-boundary fact, and
root-end offset; retains all input/value charges; and publishes `Failed` last.
No other error path may leave or clear the same scope again. Abort uses the same
depth/frame invariant and may publish an already-retained terminal parser
diagnostic only when the caller supplied no primary; it never synthesizes any
other diagnostic and always preserves an existing primary. Reset first
completes the same discard, then constructs a fresh operation. Neither can
refund charges.

Ordinary catchable exceptions from initialize, Step, final Step, terminal
observation, copy, or conversion invoke nonraising parser abort and budget/frame
discard, mark the reader failed, clear deterministic local outputs where that
handler is reached, and re-raise the primary exception. Cleanup failure cannot
replace it. The accepted scalar boundary still applies: asynchronous task abort
or another abnormal transfer during a by-reference output copy can leave that
output actual unspecified, must propagate, and requires discarding the reader
and private adapter candidate rather than resetting/reusing them. Reset and
Abort are the only recovery/discard operations after ordinary status failure;
Abort is idempotent, charge-free (it creates no new debit), nonraising, and
preserves an existing diagnostic. It may still mutate `Decode_Budget` by
leaving every scope that this reader entered.

## Closed transition tables

| Operation state | Required invariant | Legal transition |
| --- | --- | --- |
| `Uninitialized` | empty root/stack/terminal/document fact | successful Initialize/Reset to `Ready`; Abort to `Failed` |
| `Ready` | `Root_Ready`, depth zero, pending `Document_Begin` only | first `Prepare_Value` to `Active`; Reset/Abort |
| `Active` | root in progress or complete; stack/terminal binding matches tables below | traversal/value/Finish; Reset/Abort; failure to `Failed` |
| `Complete` | root complete, depth zero, no terminal, exact `Document_End_Seen`, physical EOF accepted | idempotent Finish; observation; Reset/Abort |
| `Failed` | budget depth zero, no frames/terminal/document fact | idempotent Abort or successful Reset |

Every resolver first assigns deterministic outputs, preserves a prelatched
error, validates operation/root/depth/kind/phase and exact terminal binding,
then classifies the uncharged source. Wrong-context syntax fails before charge.
Only a valid row below may charge/replay; it validates all resulting events,
then clears the binding and publishes the state/output shown last. A valid
sequence/record closer lookahead performs no charge/replay: it publishes
exhausted and rebinds the terminal to the exact matching `End_*` row.

The next table applies when a terminal binding exists.

| Terminal resolver and owner | Contextually valid suffix | Publication after success |
| --- | --- | --- |
| root `Finish_Document` | trailing whitespace or physical EOF; `,`/`]`/`}` are invalid | one `Document_End_Seen`, then `Complete` only after `Document_Complete` |
| sequence `Next_Element` | whitespace, comma, or `]` lookahead | whitespace replay clears and continues in the same call without a public result; comma path publishes next child; direct `]` rebinds without replay and publishes exhausted |
| sequence `End_Sequence` | exact rebound `]` after exhausted | replay/clear, Array_End, pop/leave, containing value finish |
| record/variant `Next_Field` | whitespace, comma, or `}` lookahead | whitespace replay clears and continues in the same call without a public result; comma path publishes next field; direct `}` rebinds without replay and publishes exhausted |
| record/variant `End_*` | exact rebound `}` after exhausted | replay/clear, Object_End (and variant Array_End), pop/leave, containing value finish |
| optional `End_Optional` | whitespace then exact `]` after none/finished child | resolves optional-tag/child terminal, Array_End, pop/leave, containing value finish |
| map key `Finish_Value` | whitespace then exact comma | child start publishes `Map_Value_Ready` |
| map value `Finish_Value` | whitespace then exact entry `]` | Array_End publishes `Map_Needs_Entry` |
| optional-some/variant-alternative/bytes internal resolver | the exact next representation separator/closer | clears representation terminal before public frame/value result |

The two map child rows are internal same-call transitions. They cannot leave a
terminal binding for a later public `Next_Map_Entry`: the key comma and value
entry closer are resolved before the matching child call returns. A subsequent
`Next_Map_Entry` therefore starts in `No_Pending_Terminal` and owns its outer
comma-or-closer classification.

With `No_Pending_Terminal`, ordinary first-item traversal uses this separate
table; it never claims to resolve a scalar terminal.

| No-pending operation | Valid uncharged source | Publication after success |
| --- | --- | --- |
| first sequence element | whitespace then value-leading byte, or direct `]` | item charge + `Child_Ready`, or exhausted |
| subsequent sequence element after a completed child | zero or more whitespace followed by either direct `]`, or comma + zero or more whitespace + a value-leading byte | exhausted, or comma replay + item charge + `Child_Ready` |
| first record/variant field | whitespace then name quote, or direct `}` | decoded name + colon + item charge + `Child_Ready`, or exhausted |
| subsequent record/variant field after a completed child | zero or more whitespace followed by either direct `}`, or comma + zero or more whitespace + a name quote | exhausted, or comma replay + decoded name + colon + item charge + `Child_Ready` |
| first map entry | whitespace then `[`, or direct outer `]` | entry Array_Begin + item charge + `Map_Key_Ready`, or exhausted |
| subsequent map entry after the prior entry closer | zero or more whitespace followed by either direct outer `]`, or comma + zero or more whitespace + `[` | exhausted, or comma replay + entry Array_Begin + item charge + `Map_Key_Ready` |
| `End_Sequence`/`End_Record`/`End_Variant` after exhausted | exact closer(s), with no child or terminal binding remaining | closer events, pop/leave, containing value finish |
| `End_Map` after exhausted | exact outer `]`, with phase `Map_Needs_Entry`, exhaustion set, no active entry child, and no terminal binding | Array_End, pop/leave, containing value finish |
| `End_Optional` after none or a completed child | zero or more whitespace followed by exact `]`, with no child or terminal binding remaining | Array_End, pop/leave, containing value finish |
| root `Finish_Document`, boundary not yet seen | exactly one zero-source `Document_End` at `Root_End_Offset`, which may precede the first trailing-whitespace byte; then trailing whitespace and physical EOF | atomically publish `Document_End_Seen` and `Complete` only after exact `Document_Complete` validation |
| root `Finish_Document`, boundary already seen with a container closer | trailing whitespace then physical EOF; another `Document_End` is invalid | preserve the one copied boundary fact and publish `Complete` only after exact `Document_Complete` validation |

“First” and “subsequent” are explicit frame phases; they are not inferred from
whether the immediately preceding child was scalar or structural. If a
retained whitespace terminal is replayed and cleared, the same public call
continues through the applicable no-pending row. A subsequent row never admits
a new child without its comma. An `End_*` row is legal after exhaustion
whenever no child or terminal binding remains, including after a scalar
terminal was resolved through retained whitespace.

At root, scalar or root-container completion records `Root_End_Offset`. An
ordinary child completion records `No_Child`; map completion publishes only the
post-resolution phase. A nonempty terminal state is permitted only alongside
the exact root/ordinary-child/optional-tag completion described above. A
structural child close completes without scalar terminal state; its following
parent separator remains ordinary unadmitted source.

## Required evidence before freeze

Differential tests run every existing direct reader fixture and root adapter
against the public oracle and private reader. They compare values, complete
output clearing, error code/path/byte offset, public cursor, completion, and
every budget counter at each operation boundary. The matrix includes:

- empty, singleton, nested, and mixed scalar/container sequences;
- map key/value phase misuse, missing/extra children, and nested entries;
- records with empty/arbitrary-bound names, duplicates, aliases, unknown-field
  adapter policy, escaped names, and capacity failures;
- arbitrary lower/upper bounds and null arrays for byte destinations, field
  names, variant alternatives, enumeration literals, and every clearing path;
- optional none/some, invalid tags/cardinality, and nested optional presence;
- optional-some item denial proves both readers return `Present = False`, no
  frame, and budget depth zero after the public oracle fix;
- nullary/payload variants, invalid envelope shapes, and alternative capacity;
- enumeration and raw byte envelopes, including escaped-lookalike rejection;
- every separator/closer whitespace and input-denial point, item/depth limits,
  exact local-stack boundary, and error-path preservation;
- every terminal state crossed with context: the same comma/`]`/`}` is a
  charged valid separator/closer for its owning map/sequence/record/optional
  phase but uncharged `Syntax_Error` at root or under the wrong parent;
- retained/deferred/unclassified terminals at every parent transition, with
  exact Syntax-versus-Capacity precedence, single replay, owner mismatch, and
  binding-clear assertions;
- each operation-local candidate terminal—variant alternative, record name,
  bytes envelope name, bytes payload, and optional-some tag—crossed with
  retained, deferred-invalid, unclassified-exhausted, wrong-context, exact
  input-budget, and one-past-budget cases; each case proves synchronous
  resolution before publication, deterministic output clearing, and that no
  persistent terminal binding or parser window survives the call;
- retained and unclassified `]`/`}` two-stage lookahead rebinds, matching End
  replay/denial, and wrong-End-owner rejection without lost windows;
- structural kind/source/raw-byte mutations, missing/extra/reordered events,
  root-close plus `Document_End`, and zero-progress failures;
- prelatched calls, call-order misuse, abort/reset from every frame/phase,
  normal-failure budget depth zero at the failing boundary, exception cleanup
  at each driver boundary, and adapter rollback; and
- `Skip_Value` raw depth/item/text/input bounds, nested logical-depth plus raw-
  depth exact/one-past cases, and exact derived work traces across every JSON
  kind.

The root build, assertion-enabled suite, test-hook-elision scan, dependency
attestation, forbidden dependency/ALI scan, 110-column scan, and diff check are
mandatory. Independent architecture and implementation reviews must resolve
all P0/P1 and normally P2 findings before commit.

## Architecture review record

Two independent full-file reviews and their narrow fix re-reviews closed on
2026-08-26 with P0 none, P1 none, and P2 none. The reviewed closure includes
the first/subsequent separator grammar, exact map and optional phases,
once-only root `Document_End`, terminal ownership and replay, remaining-depth
raw skipping, common poison/unwind, and the required mutation and parity
evidence. The shared Wire boundary review separately reported P0/P1/P2 none.

## Map implementation review record

The map implementation and its fix revisions received two independent diff
reviews. The final reviews reported P0 none, P1 none, and P2 none. Fixes made
during review covered successful reverse nesting, whitespace at every map
representation boundary, exact item-limit traces without a public test
observer, exceptions during scalar and popped-container map resolution,
abort/reset from every implemented map phase, call-order misuse, and ownership
of the outer map closer.

The final verification ran the root build and assertion-enabled tests, the
Flyology JSON dependency and Python checks, test-hook elision, every maintained
Ada and Python generator gate, release-marker and fixture-manifest checks, APM
0.28.0 install/compile/audit reproduction, formatting, and diff checks.

## Optional implementation review record

The optional implementation and two fix re-reviews closed with P0 none, P1
none, and P2 none. Review fixes made the optional frame retain its exact
presence phase, require the mandatory tag terminal for `none`, require the
exact child terminal or no terminal for `some`, and reject every inapplicable
number-event payload before publishing the frame. No synthetic corruption hook
was added: the state is not caller-constructible or mutable through the private
API, both valid branches are covered, and the complete defensive truth table is
explicit in `End_Optional`. Omitting the hook is a scoped test-design decision,
not a language-security claim.

Differential tests cover root and nested none/some values, optional and
sequence/record/map nesting in both directions, optional map keys and values,
item/value/depth limits, every input boundary including literal-preflight
retention, a source ending at `Positive'Last`, prelatched output, call-order
misuse, abort/reset with and without a primary diagnostic, driver exceptions,
structural and number transcript mutations, parent-map resolution after pop,
and real root-adapter commit/rollback after a closer or trailing-document
failure. The exact whitespace-rich denial trace retains 0, 1, 2, 3, 4, 5, 6,
6, 6, 6, 10, and 11 bytes for limits 0 through 11 while reporting the matching
denial offsets.

Final verification passed the root build and assertion-enabled tests, both
Flyology JSON lock attestations and their Python suite, test-hook elision, the
Ada generator build/scaffold/smoke suite, all 12 Python generator tests,
release-marker and fixture-manifest checks, the generated-fixture crate, all
10 APM 0.28.0 audit checks, formatting, the 110-column scan, and
`git diff --check`.

## Enumeration and variant implementation review record

The enumeration and variant implementation and both fix re-reviews closed with
P0 none, P1 none, and P2 none. Enumeration retains its distinct format-neutral
operation while sharing the exact JSON string transcript. A variant owns one
Serde logical value and depth scope across its private array, alternative-name,
and object representation; only the object fields consume logical items and
child values.

Review found and fixed nested exception cleanup in the shared string collector.
The private driver now latches an abort once per parser operation, Reset clears
that latch only after beginning a fresh operation, and shared string/name event
validation checks exact raw, decoded-source, decoded-form, Unicode, unused-byte,
and Boolean-payload facts. Exception traces prove one parser abort at every
reachable Begin/End driver boundary, idempotent repeated abort, prelatched Reset
inertness, and a fresh abort after successful Reset.

Differential tests cover nullary and payload variants, escaped Unicode
alternatives, exact and one-past alternative capacity, deferred invalid
followers, every structural event mutation, absolute input/value denial traces,
item/text/depth limits, a source and destination ending at `Positive'Last`,
nested sequence and map key/value traversal, call-order and wrong-End misuse,
abort/reset from every variant phase with and without a primary diagnostic,
exceptions after variant pop during map-parent resolution, and real root-adapter
commit/rollback after the final closer or trailing-document failure.

Final verification passed the root build and assertion-enabled tests, both
Flyology JSON lock attestations and their seven Python tests, test-hook elision,
the Ada generator build/scaffold/smoke suite, all 12 Python generator tests,
release-marker and fixture-manifest checks, the generated-fixture crate, all 10
APM 0.28.0 audit checks, formatting, the 110-column scan, and
`git diff --check`.
