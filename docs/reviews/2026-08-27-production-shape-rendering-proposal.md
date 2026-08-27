# Production-shape lowering and rendering proposal — 2026-08-27

## Problem

The Ada generator's retained lowered model and renderer describe only a single record whose fields are Boolean,
signed-integer, or modular-integer scalars. The reviewed Type IR extractor's first production fixture is a graph:
two enumerations, a one-dimensional constrained array indexed by one enumeration and containing the other, and a
public definite record containing the value enumeration and array. Serde cannot lower or render that graph, so
publishing the Type IR extraction API alone would still leave production generation unable to succeed.

This change must not claim production extraction authority. The Type IR v2 query and
`Production_Checked_Document` surface is unpublished, and the generator must continue returning
`Type_IR_API_Unavailable` until it consumes a reviewed published API in the extraction process.

## Proposed boundary

Extend the scalar-record-specific retained model with a Serde-owned, limited-controlled lowered graph. The legacy
inline scalar-record representation remains temporarily to preserve the already reviewed golden fixture surface
while the production frontend is unavailable; no new production shape is lowered into it. The graph is an
offline generator value and is not installed with or referenced by the runtime crate. It contains only logical
adapter policy and Ada names already authorized by the eventual overlay/lowering transaction:

- type nodes for Boolean, exact signed integer, exact modular integer, enumeration, one-dimensional constrained
  array, and public definite nonlimited record;
- per-enumeration logical type names plus literal Ada names, primary presentation names, and presentation aliases
  in semantic declaration order;
- array index-type and component-type references;
- the root record's independently overlay-authorized logical type name, component Ada names, one primary
  presentation name per component, and value-type references in declaration order;
- one explicitly selected root record, output unit, required `with` units, and the existing runtime limits.

The limited-controlled owner retains exact-sized allocated node, literal, alias, and field tables. Text uses the
existing lowered-model bounded text representation and its already reviewed intrinsic capacity. Counts are derived
from the checked Type IR and overlay under `Maximum_Type_IR_Nodes`, decoded-text limits, and the one existing
operation budget; the graph adds no public default or new independent schema-count ceiling. A private builder first
checks every count, byte length, sum, product, and conversion, charges the complete construction operation in the
documented order, then allocates and fills an unpublished candidate. It marks the fresh owner valid only after
complete graph validation. No operation rebinds an already valid owner. A narrowly caught table-allocation
`Storage_Error` poisons the operation budget, finalizes the unpublished candidate, and reports
`Resource_Exhausted`; unrelated exceptions remain `Internal_Error`. Accepted charges are never refunded.
Finalization is ledger-free, nonraising, and releases every partial table. The private child
`Flyology_Serde_Generator.Rendering` unit consumes only synchronous read-only lowered-model queries. No table access,
vector, cursor, or borrowed String escapes that call; the existing bounded text slices are copied as immutable values.
Rendering builds both artifacts in a private candidate and
leaves the caller's prior artifacts unchanged on every non-success status. No Type IR view, cursor, access value,
stable ordinal, or production capability is retained by the graph.
Each named node also retains the ordinal of its extractor-attested defining `with` unit. Rendering uses that binding
directly; it never reconstructs a library-unit dependency by splitting an Ada selected-name spelling. Before a test
or future production builder marks the attached unpublished graph valid, it runs the same semantic validator and
measure-only
specification/body emission used by rendering. Invalid references, names, dependencies, runtime limits, or overlong
generated lines therefore cannot escape in an apparently valid owner. Measure-only emission retains no artifact and
charges no rendered bytes.

The builder's first gate is the caller's existing diagnostic and budget state. A prelatched diagnostic is a strict
no-op even when the budget is also poisoned and preserves that primary. With a clean diagnostic, a prepoisoned
budget performs no query, validation, charge, allocation, cleanup callback, or owner mutation but sets
`Resource_Exhausted`. From a clean active state, a denied atomic work reservation poisons the budget once, reports
`Resource_Exhausted`, publishes nothing, and retains every earlier accepted charge. Count, text-length, arithmetic,
or construction-formula representability failure reports `Unsupported_Lowered_Model` before charging. Semantic
graph validation occurs only after the accepted reservation and candidate fill; a self/back/kind/name/reachability
or other semantic rejection reports `Unsupported_Lowered_Model`, retains that debit without poisoning, finalizes
the candidate, and leaves the default or prior owner unchanged.
For a semantically invalid graph with a one-less budget, reservation denial precedes semantic inspection and returns
`Resource_Exhausted` with poison and the one failed charge point; with the exact budget, reservation succeeds and the
later semantic rejection retains the complete debit without poison. Both traces are normative tests.

Let `T`, `F`, `L`, `A`, and `W` be the counts of type nodes, fields, structural enumeration literals, presentation
aliases, and required `with` units. Let `S` be the checked sum of bytes in every retained Ada, logical, primary,
alias, output-unit, and `with` text. Type nodes, fields, literals, and required-with bindings are
extractor-attested structural inputs; construction requires `T + F + L + W <= Maximum_Type_IR_Nodes`. Overlay
policy items are counted as `2 + V + L_v + A + F`, where the two are output/root logical names, `V` is the number of
value-reachable enums, and `L_v` their literal count; this must not exceed `Maximum_Overlay_Nodes`. Every text is at
most both the existing bounded-text capacity and `Maximum_Decoded_String_Bytes`. Before any allocation or owner
mutation, the builder checks all conversions to `Natural`, sets `M = T + F + L + A + W`, and reserves exactly
`1 + (M + 1) * (S + M + 1)` work units in one `Charge_Work` call. This includes the worst-case byte work for every
pairwise name comparison as well as table/reference/reachability work. Overflow or a value outside `Natural` rejects before
charging; budget denial poisons the existing operation budget and publishes nothing. The closed quadratic
reservation owns table construction, every reference and kind check, name comparison, namespace/with check, and
whole-graph reachability pass; those operations make no nested charge. Exact and one-less tests assert the formula
and debit order. Input/query layers retain their own already documented charges, so bytes are not double charged.
One private nonraising arithmetic helper computes this formula for both construction and rendering. It returns an
explicit unrepresentable result before an overflowing addition or multiplication; direct tests cover zero, the
fixture total, the largest representable `Natural` result, and adjacent arithmetic rejection boundaries. The
accepted owner retains that exact checked work amount as an immutable invariant. Rendering may read this scalar
before reservation, but after reservation it recomputes the graph totals and rejects any mismatch before output
allocation or publication.

Each render call independently reserves the same exact `1 + (M + 1) * (S + M + 1)` work amount before graph
inspection, line measurement, artifact allocation, or prior-artifact mutation. It owns node, field, literal, alias,
required-with, reference, namespace, and line-cap traversal. Formula overflow reports
`Unsupported_Lowered_Model` without charge or poison; denial poisons and reports `Resource_Exhausted`. Actual output
scanning and copying are owned separately by the existing one-work-unit-per-emitted-byte rendered-chunk charges and
are not included again in the graph reservation. Repeated rendering reserves the graph amount again. Exact and
one-less render traces verify both stages and prior-artifact preservation.
An already poisoned render budget is checked before graph inspection and returns `Resource_Exhausted` without a
new charge, line measurement, artifact allocation, or prior-artifact mutation.

References are generator-private local ordinals. Validation requires a topological order: every array or record
component reference names an earlier compatible node. The graph contains exactly one record and that record is the
selected final/root node. Array elements may be Boolean, exact signed, exact modular, or enumeration nodes; arrays
of arrays and records are rejected in this first slice. Every node must be reachable from the root through a field,
array-element, or array-index edge. Validation rejects self, back, forward, missing, disconnected, and incompatible
references before indexing; duplicate Ada or presentation names in the same lookup/declaration domain; invalid or
colliding selected/helper names; unsupported type shapes; an array rank other than one; a non-enumeration index;
and any scalar that cannot use the exact existing runtime adapter. There is no rounding, truncation, default
inference, or physical-representation lowering.

The eventual Type IR lowerer has a closed fail-closed structural gate. Apart from predefined Boolean, every node is
a directly visible named public type declaration, not a subtype, derived/private/full/incomplete/class-wide view or
anonymous type. Every declaration has Known `definite = true` and Known false `limited`, `tagged`, `class_wide`,
`abstract`, `contains_access`, `task`, `protected`, `controlled`, `contains_controlled`, and `predicate` facts. The
record is nondiscriminated, nonvariant, nonnull, and has Known component visibility. Its components are nonaliased,
nonconstant, have no defaults or variant paths, and reference only assignment-safe nodes. The array is Known
constrained, rank one, and has a Known static constraint exactly spanning the complete nonempty enumeration index
type. Its component is assignment-safe and its index and element declarations are both directly nameable. All
other forms and any Unknown/Unsupported mandatory fact are rejected before rendering. Ada invariants or other
value-affecting contracts must be explicitly attested absent by the extractor/production capability; production
stays unavailable if the published Type IR query/authority cannot prove that fact.

Every record-component, array-component, and array-index type-reference slot must name the exact accepted
declaration and have an explicitly present Known-false use-site-constraint fact and explicitly present Known-false
null-exclusion fact. Unknown, Unsupported, absent, or true rejects. Only the separate array-dimension constraint may
carry the reviewed Known static full-range constraint. A constrained subtype indication, anonymous constraint,
null exclusion, or other use-site restriction rejects the document rather than being reduced to its base node.

Exact scalar gates are part of that structural check. Signed bounds and staticness are Known, both exact decimal
bounds fit `Interfaces.Integer_64`, and the named type's attested bounds match them. Modular staticness, zero low
bound, high bound, and modulus are Known; the high bound fits `Interfaces.Unsigned_64`, modulus is exactly high plus
one in arbitrary-precision decimal, and the attested named type matches. Enumeration literal ownership, count,
declaration order, bounded semantic positions, and attested Ada literal names are exact. Ada unit, type, component,
and literal names come only from the extractor-attested binding/context and cannot be supplied or redirected by the
overlay; required-with names and closure are likewise extractor-attested, structurally charged as `W`, and must
cover every selected type. The overlay may neither add nor redirect a unit. It owns only output placement,
logical/presentation/alias policy, and runtime limits.

Only defining-identifier enumeration literals are accepted. Defining character literals are legal Ada but are
rejected by this initial lowerer because their source spelling and qualification are a distinct rendering form.

Enumeration declaration order is used only to enumerate Ada literals. Ada enumeration representation values are
not read or emitted. Literal presentation names and aliases remain Serde overlay policy. The test constructor may
provide fixed names solely to exercise rendering; it is not production lowering and is inaccessible to the
production entrypoint. Root record field aliases and defaults are explicitly unsupported in this slice; the
existing generated record policy continues to reject duplicate and unknown fields and require every primary field.
An enumeration reached through a record field or array-element edge is value-reachable and requires the logical,
primary, and alias metadata above. An enumeration reached only as an array index retains only its Ada name, literal
count/order, and full-range structural facts; the renderer emits no unused Serde enumeration adapter for it. If the
same enumeration is also value-reachable, the ordinary value metadata and adapter are required exactly once.

All emitted presentation and logical strings are nonempty printable ASCII bytes `16#21# .. 16#7E#`. Quotes are
doubled by the Ada source-literal emitter; controls, space, NUL, CR, LF, non-ASCII, and invalid UTF-8 are rejected.
This is an explicit generator support boundary, not a runtime text restriction. Ada identifiers and selected names
remain ASCII and are compared case-insensitively in their actual declaration domains. Required `with` units are in
deterministic input order and cannot duplicate each other, equal an ancestor or descendant of the output unit, or
collide with a generated runtime context unit. Synthesized helper identifiers use a closed ordinal namespace, are unique by construction, and are
validated against every other generated declaration in their scope.
Output placement that is equal to, an ancestor of, or a descendant of any attested defining unit is itself
unsupported; implicit parent visibility therefore never substitutes for a required-with binding.

## Rendering

The renderer remains Serde-owned and emits one package for the selected root record. It uses the existing runtime
adapters without introducing a new runtime traversal:

- Boolean calls the format-neutral scalar operations directly;
- signed and modular nodes instantiate the existing exact integer adapters;
- enumeration nodes emit bounded, nonallocating metadata functions and instantiate
  `Flyology_Serde.Adapters.Enumerations`;
- fixed-array nodes emit synchronous element wrappers and instantiate a new
  `Flyology_Serde.Adapters.Fixed_Arrays` with the named index, element, and array types;
- root-record fields call the adapter associated with their referenced type.

The new format-neutral fixed-array generic uses a constrained formal array type,
`type Array_Type is array (Index_Type) of Element_Type`, because Ada rejects the production fixture's constrained
`Palette` type as an actual for the existing unconstrained formal in `Constrained_Arrays`. The existing generic and
its behavior remain unchanged. `Fixed_Arrays` uses the named array type's complete range as authority, emits a known
exact length, creates one unpublished `Array_Type` candidate, rejects short or long input, calls `End_Sequence`, and
assigns the target only after success. The initial generator gate accepts only the complete nonnull index-type range;
nonfirst subtype, partial, and null constraints are rejected until they have a separately reviewed lowering policy.
On serialization, a prelatched error is a no-op; `Array_Type'Length > Natural'Last` returns `Unsupported_Value`
before `Begin_Sequence`. On deserialization, a prelatched error is also a no-op. The fixed target length is checked
against `Natural'Last` and `Policy.Limits.Maximum_Container_Items` before `Begin_Sequence` or candidate declaration.
After `Begin_Sequence`, a Known mismatching length returns `Out_Of_Range`; Unknown length is accepted. The adapter
then declares one local candidate, consumes exactly one element per target position with the existing zero-based
path index, rejects a missing or extra element, and calls `End_Sequence`. Successful element paths are popped;
failure retains the failing path for the root error and root abort performs traversal cleanup. The target changes
only after successful `End_Sequence`. Adapter or allocation exceptions propagate after Ada finalizes the local
candidate; the root transaction aborts and preserves the caller's prior published value.

Generated enumeration matchers compare complete names. Alias metadata is stable for one operation, and duplicate
or ambiguous names are rejected before artifact publication. Array decoding continues to build an unpublished
exact-range candidate and assigns it only after exact cardinality and `End_Sequence` succeed. The root record keeps
the existing unpublished candidate/commit/rollback protocol, including duplicate, unknown, and missing-field
policies.

Generator-private adapter/helper identifiers are validated Ada identifiers and are neither Type IR identities nor
wire tags. The existing scalar-record body intentionally gains the same fresh-builder rejection and
`Candidate := Published` retry repair as the graph renderer. The Python oracle, Ada renderer, checked-in golden,
compiled fixture, and recomputed generator-source digest must agree on that semantic change. The new graph fixture
adds a separate generated package without changing the runtime JSON or CBOR representation.

## Scope and evidence gates

The root-record field-input buffer is rendered at the selected runtime `Maximum_Text_Length`, so every in-budget
unknown name reaches deterministic unknown-field policy instead of failing at the longest known name. Generated
enumeration instances likewise pass `Maximum_Text_Length` as their input-name capacity; their declared primary and
alias maxima remain separately derived and checked by generated metadata validation. Every logical, primary, and
alias name must fit that runtime limit. This first bounded slice also requires
`Maximum_Text_Length in 1 .. 128`, matching the existing intrinsic lowered-text capacity, so neither generated stack
buffer can be made unbounded by policy; 129 is rejected before rendering. Before emitting, validation constructs or measures every possible generated line and rejects
a combination that would exceed 110 columns; the 128-byte retained capacity does not imply every combination can be
rendered.

This slice does not change the overlay schema, accept persisted Type IR as authority, call the unpublished Type IR
API, publish artifacts to a destination, or remove `Type_IR_API_Unavailable`. It closes the renderer/lowered-shape
gap needed immediately after the Type IR API is pinnable.

Before the change may freeze:

1. The existing wire-record golden is regenerated for the intentional builder repair above. After stripping the
   validated seven-line header, the Python oracle, Ada renderer, and checked-in payload are byte-identical; the new
   source digest is attested, and compiled JSON/CBOR plus fresh-builder/failure/retry tests remain green.
2. A checked-in `Production_Shapes` source with `Position`, `Color`, `Palette`, and `Packet` is represented by a
   test-only lowered graph, rendered, compiled from a clean generated directory, and round-tripped through both
   JSON and CBOR using nonfirst enumeration values and all array positions.
3. Generated JSON tests cover every enum primary and alias on decode, primary-only encoding, unknown names, a custom
   Ada enumeration representation clause, exact/short/long arrays, duplicate/unknown/missing record fields, retry,
   and preservation of a previously published root after every failure. Generated CBOR tests cover the same complete
   graph's roundtrip plus truncated-input rollback. The already reviewed direct `Fixed_Arrays`, JSON, and CBOR runtime
   suites remain authoritative for injected late-element and `End_Sequence` failures, exact container/logical-event
   limits, and the broader backend policy matrix; this milestone instantiates that unchanged generic and does not
   duplicate its backend conformance suite in generated code.
   Unknown field and enumeration names are tested at known-maximum plus one, exactly `Maximum_Text_Length`, and
   runtime maximum plus one; the first two reach `Unknown_Field` or `Invalid_Value`, while the last reaches the
   backend text-capacity error.
4. Negative graph-owner/renderer tests cover invalid/self/back/forward/disconnected references, missing, redirected,
   and unused defining-with bindings, duplicate/ambiguous enum names, runtime-unit collisions, irrelevant metadata,
   overlong generated lines, exact and one-less construction budgets, formula boundaries, injected allocation
   failure, complete nonraising partial-owner cleanup, prelatched/prepoison no-op and denial precedence, and the
   exact `1 + (M + 1) * (S + M + 1)` construction-work debit.
   Direct precedence tests cover prelatched plus active budget, prelatched plus poisoned budget with the primary
   preserved, and clean diagnostic plus poisoned budget returning `Resource_Exhausted` without a new charge.
   Invalid-graph budget snapshots prove the accepted construction debit remains consumed without poisoning; separate
   formula failures prove zero debit. Partial/null/nonstatic constraints, use-site constraints, unknown/unsupported
   structural facts, declaration-form eligibility, overlay attempts to add bindings, defining-character literals,
   and exact Ada type-relation identity remain mandatory tests for the future Type IR/reflection lowerer before that
   production authority can mint this already validated graph owner; this renderer milestone has no such query seam.
5. Test-only construction uses the same graph owner, structural validator, semantic validator, and measure-only
   rendering preflight that the future production lowerer must use. Its source exists only in the test GPR source
   directories; clean production object-tree and executable scans prove that no test constructor or fixture symbol is
   linked into the production generator.
6. Generated-source and compiled ALI/object scans prove no Type IR, Libadalang, Wire, JSON event-parser, or
   generator dependency escapes into the runtime artifact.
7. Direct `Fixed_Arrays` tests cover prelatched calls, Known and Unknown lengths, exact/short/long cardinality,
   `Natural'Last`/container-limit ordering where representable, path balance and retained failing paths, element and
   `End_Sequence` failure, target preservation, and candidate `Storage_Error` propagation. A statically selected
   test-only pre-candidate hook injects that failure; disabled source selection and ALI/object scans prove the hook
   and sentinel are absent from production. Matching enabled and disabled private hook specifications expose literal
   `Enabled : constant Boolean := True` and `False`; the disabled form declares only an imported sentinel, and every
   body/helper reference is inside the literal static guard. `scripts/check-test-hook-elision.sh` builds both source
   selections under `-O0` and `-O2` and proves the disabled sentinel absent. Generated record tests
   cover exact 64-byte acceptance and 65-byte backend-capacity rejection with prior root preservation. The direct
   record/enum adapter suites retain their independent maximum-name boundary coverage.
8. An injected post-table unrelated generator `Storage_Error` is classified `Internal_Error`. Artifact allocation
   and emission deliberately have no narrow handler and reach that same outer classification; only the narrowly
   caught lowered-table allocation maps to `Resource_Exhausted`.
9. The generator build, scaffold/smoke/renderer suites, generated-code fixture suite, root runtime suite, release
   marker/manifest checks, clean GNAT 15.3.1 and GNAT 16.1.0 builds of the generated full-range `Fixed_Arrays`
   instance, APM audit, formatter, line-length scan, and `git diff --check` pass. A container-limit rejection trace
   proves no begin event or candidate hook occurs. Render-budget tests include the prepoison
   no-inspection/no-mutation trace. Exact type-reference rejection evidence belongs to the future production-lowerer
   gate identified in item 4, not to this renderer-only milestone.
10. Independent architecture and implementation reviewers report P0/P1 none and fix P2 by default.

Severity for this review is: P0 permits authority substitution, unsafe publication, or runtime coupling; P1 can
generate incorrect Ada/Serde behavior, lose structural meaning, retain an invalid lifetime, or leave a required
path untested; P2 is a bounded diagnosability, maintainability, or portability defect that should normally be fixed.

## Review record

Architecture review cycle one found P0 none, P1 seven, and P2 five across the two independent reviews. The draft now
restricts the graph to exactly one root record and supported earlier scalar/enum/fixed-array nodes; adds enum logical
names; removes unsupported record-alias claims; defines exact Type IR fact/view/form gates; defines printable-ASCII
source emission and case-insensitive namespace checks; closes limited-owner construction, charging, publication,
and finalization; removes the root-edge exception; adds whole-graph reachability and reference validation; corrects
the provenance-header gate; and expands failure/isolation evidence. A compiler spike independently found that the
existing unconstrained-array formal cannot accept the constrained production `Palette`; the corrected proposal adds
the distinct `Fixed_Arrays` adapter and leaves `Constrained_Arrays` unchanged.

Architecture fix re-review cycle two found P0 none, P1 two, and P2 three. It otherwise closed the entire first-cycle
finding set and accepted the `Fixed_Arrays` split. The draft now makes rendering a trusted ordinary child that
cannot leak private table access; defines the exact count ownership, quadratic construction-work formula, one atomic
charge and denial order; separates index-only enum structure from value enum Serde metadata; removes an unreachable
generated ambiguity test; and rejects case-insensitive output-unit ancestor/descendant `with` dependencies.

The parallel safety re-review found P0 none, P1 five, and P2 five against the earlier revision. The live draft now
names the root logical metadata explicitly; gives the same closed construction formula/order above; closes signed,
modular, enumeration, attested-binding, required-with, and value-affecting-aspect gates; defines complete
`Fixed_Arrays` status, limit, path, target, and exception ordering; replaces the fixed 64-byte generated field buffer
with the exact validated maximum; separates runtime and generator limit tests; and requires the unrelated
`Storage_Error` classification repair. Compiler-spike build artifacts were moved out of the worktree before staging.

Architecture fix re-review cycle three found P0 none, P1 five unique findings, and P2 six across both reviewers.
The live draft now sizes inbound record and enum names from runtime text policy rather than known metadata; rejects
all unrepresented use-site constraints and null exclusion; makes required-with bindings structurally attested and
assigns their limit ownership; makes prelatched/prepoison precedence normative; gives each render its own exact
graph-work reservation; accepts only identifier enum literals; defines formula-overflow status; rejects output
placement that would rely on implicit parent visibility; and makes fixed-array failure injection and both clean
compiler matrices reproducible.

The safety side of cycle four found P0 none, P1 two, and P2 three. The live draft now separates uncharged
representability gates from charged semantic validation and preserves the accepted debit on semantic rejection;
bounds the generated runtime text buffers at the existing 128-byte intrinsic capacity; makes render-prepoison
behavior exact; and adds fact-presence and record/enum boundary evidence.

Architecture fix re-review cycles four and five found, across both reviewers, P0 none; P1 five, then one; and P2
four, then none. Corrections closed runtime-sized but bounded inbound name buffers, exact use-site fact presence,
required-with authority and limit ownership, construction-versus-render accounting, semantic-invalid debit order,
identifier-only enum forms, output visibility, test-hook mechanics, and clean-diagnostic/prepoison precedence. Both
independent final architecture reviewers now report P0/P1/P2 none. The architecture is frozen for implementation.

Implementation review cycle one found P0 none and P1/P2 issues in work-reservation ordering, unpublished-builder
state, complete generated-line validation, checked formula arithmetic, allocation-error classification, defining-unit
authority, semantic validation before owner publication, stored-work integrity, query preconditions, and missing
failure/isolation evidence. The implementation now uses one checked formula helper; stores an attested defining-with
ordinal per node; validates and dry-renders before publishing a graph; rejects uninitialized generated builders;
narrows allocation exhaustion; preserves prior artifacts; injects allocation, unrelated `Storage_Error`, and internal
failure with complete unpublished-owner cleanup assertions; and adds production/test dependency scans.

Implementation fix review found P0 none, P1 none, and two remaining P2 evidence defects. The owner oracle now remains
live across candidate-to-result transfer and proves cleanup for post-transfer failure. Source, ALI, and object scans
cover both generator package-name spellings. The proposal records the intentional legacy generated-builder semantic
repair, and the legacy integration suite proves fresh-builder rejection, failed rollback preservation, and successful
retry. The generated record fixture also rejects an eight-byte unknown field when its longest known field name is
seven bytes.

Final independent review reports P0/P1/P2 none. The implementation and its evidence may freeze at this milestone;
the production Type IR/reflection lowerer remains fail-closed and outside this decision.
