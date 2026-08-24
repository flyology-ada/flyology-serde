# Ada provenance-list parser proposal

Date: 2026-08-24

Status: accepted architecture contract. It authorizes implementing and testing only this private parser; it
authorizes no filesystem read, source-set acceptance, checked stage, generator identity, build, or publication
action.

## Boundary

The first snapshot-stage subcomponent is a dependency-free parser for the exact retained bytes of
`provenance-files-v2.txt`. It is a private child of
`Flyology_Serde_Generator.Build_Attestations`, not a reusable Flyology manifest API. It depends only on the parent
attestation package, `Build_Budgets`, the Ada runtime, and the disabled production test-hook specification. It does
not depend on JSON, SHA2, Libadalang, Type IR, Git, the host filesystem, or the Serde runtime.

The parser proves only that one supplied byte sequence is a well-formed v2 provenance-list claim. It cannot prove
that a path exists, is regular, is below a retained directory, names the same object later, belongs to the complete
closed source set, matches Git, or entered a compiler. The future same-read stage owns input-byte charging and
passes the exact retained bytes to this parser without reopening. The future discovery transaction must compare the
parsed claim bidirectionally with retained no-follow source observations before a `Checked_Stage` can exist.

## Private owner and operations

The child owns a limited `Parsed_List` discriminated by one nonnull `Build_Budgets.Budget` access. Its retained
payload contains the exact active session, entry count, and one insertion-ordered linked list of exact path bytes.
It retains no caller access value, source buffer alias, filesystem identity, or authority flag.

`Parse` takes `Bytes : String`, the active session, the exact retained request values for maximum per-manifest bytes,
path bytes, and source files, a limited owner, and an in-out `Parse_Status`. Production code may pass only the three
values retained by the same sealed request; independent values are test-only. The same-read stage, not this parser,
enforces `Maximum_Total_Manifest_Bytes` across manifest and lock reads. Returned bytes are input-charged exactly once
before either aggregate or per-file rejection. Parsing can succeed only into an empty owner and never replaces a
prior list.

`Parse_Status` is exactly `Parse_Succeeded`, `Parse_Session_Foreign`, `Parse_Owner_Not_Empty`, `Parse_Malformed`,
`Parse_Limit_Exceeded`, `Parse_Budget_Exhausted`, `Parse_Budget_Failed`, `Parse_Allocation_Failed`, and
`Parse_Internal_Failure`. `Parse_Succeeded` is the only enabled input. Every other input status is a zero-charge
no-op. Precedence is input status, exact owner/session, budget state, retained payload-session match when nonempty,
empty owner, structural byte bound, then parsing and allocation. A stale nonempty owner is Session_Foreign before
Owner_Not_Empty. Allocation or unexpected failure poisons an active ledger, publishes nothing, and maps to its
distinct status. Abort propagates and controlled candidates reclaim every unpublished node. Finalization is
nonraising and poisons the owner if cleanup is damaged. Every non-success preserves the complete prior owner.

The production stage consumes the parsed list internally by a scope-limited `Visit` callback. The closed
declarations are equivalent to `type Visit_Action is (Continue, Stop)` and a not-null access-to-procedure taking the
exact same `Session_Tag`, one `Path : String`, and `Action : out Visit_Action`. Path is an immediate, nonretained
view of separately owned stable bytes and is valid only during that call. The parser never calls the callback during
`Parse`; visitation is a distinct read-only operation after success. No path getter, raw node, access value, cursor,
allocation, or complete copied list is exposed.

`Visit_Status` is exactly `Visit_Succeeded`, `Visit_Session_Foreign`, `Visit_No_List`, `Visit_Reentrant`,
`Visit_Stopped`, `Visit_Budget_Exhausted`, `Visit_Budget_Failed`, and `Visit_Internal_Failure`. Visit_Succeeded is the
only enabled input. The entry gates are input status, exact owner/session, budget state, retained payload-session,
nonempty list, and inactive visit latch. Every non-success gate is uncharged and preserves the list. Visit sets the
latch only for the callback scope and clears it during every normal or exceptional exit without replacing a primary
status. Concurrent use of one list or its unsynchronized budget is forbidden; recursive Visit from a callback is
rejected as Visit_Reentrant without charging.

After every callback and before any later charge, Visit rechecks retained session and budget. Session_Foreign has
precedence, followed by Budget_Exhausted and Budget_Failed, then the callback action. Stop becomes Visit_Stopped and
is an ordinary nonpoisoning outcome. The future stage callback records its more specific mismatch in its own
unpublished controlled candidate before returning Stop. A callback exception is classified by the same
post-callback session/budget precedence; otherwise it becomes Visit_Internal_Failure and poisons the active ledger.
Task abort is never translated: it propagates, the retained list is unchanged, prior Visit charges remain, and
callback-owned candidate cleanup remains the consumer's responsibility.

Tests use a private descendant callback to compare observed paths. Test hooks are enabled only through the test GPR;
the production build selects a literal `Enabled : constant Boolean := False` imported-sentinel specification and
must eliminate every guarded reference at `-O0` and `-O2`.

## Closed grammar

The complete input is nonempty and ends in exactly one trailing LF, not one LF in the whole input. LF terminates
every entry; a second trailing LF is a blank entry and CR is never accepted. An entry is nonempty portable ASCII
using only `A`-`Z`, `a`-`z`, `0`-`9`, `_`, `-`, `.`, and `/`. It is relative, has no
leading or trailing `/`, no empty component, and no component equal to `.` or `..`. The parser performs no Unicode,
case, separator, or host normalization.

Entries are in strictly increasing unsigned-octet order. Equality and decreasing order are malformed; no separate
duplicate policy exists. The retained `Maximum_Manifest_Bytes_Per_File` bounds the supplied byte sequence before parsing,
`Maximum_Source_Files` bounds completed entries before allocating the next node, and `Maximum_Path_Bytes` bounds an
entry before allocating it. A max-plus-one supplied byte sequence reports the limit status without work; a
max-plus-one entry or entry count reports the limit status after charges already spent examining the decisive byte.
Empty input, missing final LF, blank line, invalid byte, invalid component, and ordering errors are malformed.

The list must contain exactly one `provenance-files-v2.txt` entry. It must also contain `alire.toml`,
`dependency-identities-v2.json`, and `flyology_serde_generator.gpr`. These four membership facts are necessary but
not sufficient source-set evidence. Schema, source, native, template, future source-selection, and bootstrap closure
are established only by the later independent discovery comparison; this parser does not carry a mutable allowlist.

## Parser state and cost-model v1 extension

After the uncharged whole-input bound check, Parse applies this state machine with no implementation-dependent
probe. Before examining any byte it reserves exactly one work unit. For a non-LF byte it increments the current
path length; exceeding `Maximum_Path_Bytes` reports Limit before inspecting whether that decisive byte is lexically
valid. Within the bound it validates the portable byte and separator/component state; lexical failure is Malformed.
For LF it first rejects a blank entry or unfinished invalid component, then checks whether completing the entry
would exceed `Maximum_Source_Files`. Count overflow is Limit before any ordering or required-name comparison. It
next performs the previous-path ordering comparison, then the still-unseen required-name comparisons in their fixed
order, then allocates and links the completed entry. Therefore malformed blank/component state precedes count,
count precedes order, and order precedes required-name comparison and allocation. Combined-failure tests freeze
this precedence.

At EOF, absence of the trailing LF is Malformed after all supplied bytes have been charged. When the trailing LF is
present, missing-required membership is checked from retained flags and adds no charge. Missing-final-LF and
missing-required checks never allocate or reserve another unit.

The future same-read file reader owns every `Input_Bytes` charge. `Parse` never charges input and its API comment
forbids callers from treating it as a read operation. It charges only `Work_Units` under the same request budget:

1. The status/session/budget/retained-session/owner gates and a supplied length above the retained
   `Maximum_Manifest_Bytes_Per_File` are uncharged.
2. Before examining each byte, reserve exactly one work unit. Denial leaves the prior owner empty, retains earlier
   charges, and examines no denied byte.
3. Entry-count, path-length, lexical, final-LF, and final-membership checks use state maintained under already
   charged bytes and add no probe.
4. Ordering and required-name comparisons reserve one probe and then exactly
   `min (left length, right length) + 1` work units before comparing. Comparisons occur after a line's LF is charged,
   in this order: previous-path ordering when a previous path exists, then each still-unseen required name in the
   fixed order `alire.toml`, `dependency-identities-v2.json`, `flyology_serde_generator.gpr`, and
   `provenance-files-v2.txt`.
5. Allocation, owner publication, cleanup, and finalization add no charge.

`Visit` applies the closed zero-charge gates, then for each entry reserves one probe followed by the exact nonzero
path length before invoking the callback. A denial invokes no callback for that entry. After a callback, the
session/budget/action checks above add no charge. Successful empty visitation is impossible because a parsed list
has the four required entries. The consumer does not recharge the already-paid borrowed-path observation, but must
charge its own comparisons, copies, hashes, allocations, and candidate mutation.

Charges are positive, atomic, ordered exactly as written, and never refunded or coalesced. Exact traces, every
denial point, arbitrary Ada bounds, over-limit early rejection, allocation/internal/cleanup failure, and pending
abort at node and owner transfers are conformance tests.

## Required verification and review gate

Tests cover the tracked list, one-entry and all-required minimal lists, unsigned ordering, duplicate/decreasing
entries, empty/missing/double final LF, CR, invalid/high/NUL bytes, leading/trailing/repeated separators, dot
components, portable-character boundaries, missing required entries, exact/max-plus-one byte/path/count limits,
arbitrary String bounds, every exact charge and denial point, callback scope/order/exception, stale and foreign
sessions, prelatched statuses, exhausted/failed budgets, prior-owner preservation, allocation/finalization failures,
and callback abort, stop, exception, reentrancy, session reset, and callback-caused exhaustion/poison. Parse tests
include combined path-limit/invalid-byte and count-limit/order failures. Abort-safe allocation/publication tests
prove exact cleanup. A production dependency scan and `nm` test prove no JSON/SHA2/Type-IR symbol
or enabled test-hook sentinel survives.

Architecture, implementation, and every corrective diff require independent P0/P1/P2 review. P0/P1 and normally
P2 are fixed before commit.

## Review disposition

Two independent architecture reviewers examined the initial proposal and the complete corrective diff. The first
pass required a nonexceptional callback stop channel, retained-session checks, explicit aggregate-limit ownership,
closed status sets, reentrancy and post-callback budget precedence, a total decisive-byte state order, exact EOF
charging, retained request limits, and consumer-owned callback work. The corrected contract received P0 none, P1
none, and P2 none from both reviewers. This disposition authorizes parser bodies and tests under another mandatory
change review; it grants no snapshot or build authority.

The first implementation review found P0 none and no parser/body correctness defect. It kept the change blocked on
one P1 conformance gap and related P2 audit gaps: sampled reserve denials did not prove every atomic boundary,
abort tests did not retain exact work evidence, cleanup-damage tests lacked exact ownership deltas and an
independent primary, and the production dependency audit could silently accept a missing object or an unused direct
dependency. The corrective diff adds an independent complete Parse charge trace, exhaustive Parse and Visit
reserve-prefix denial runs, exact abort charges, one-entry and `Positive'Last` cases, post-rejection content
observation, exact cleanup deltas, a foreign-session primary preserved through visit-guard damage, and required
object plus direct-ALI allowlist checks. The first corrective reviewer reported P0/P1/P2 none. The second reported
P0/P1 none but found two remaining P2 evidence gaps: equal first-entry comparison amounts could hide a reordered
required-name check, and retained-payload cleanup damage did not assert exact release counts. The final corrective
diff added a long leading-path trace with distinct required-name amounts and one-less/exact denial boundaries for
each fixed-order comparison, plus exact four-path, four-node, and one-payload release deltas. Both final independent
reviewers
reported P0 none, P1 none, and P2 none. The focused forced rebuild, functional and abort binaries, full generator
smoke suite, repository verification matrix, static style checks, and APM audit were repeated before commit.
