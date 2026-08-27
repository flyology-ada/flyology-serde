# Generic Reflection construction proposal

Date: 2026-08-27

Status: architecture proposal; no API or implementation is authorized or frozen.

## Problem

The reviewed Reflection value-view API is sufficient for a generic Serde serializer: generated `Observe` operations
lend one erased structural view, and Serde recursively maps its neutral facets into logical events. Deserialization is
not the inverse of observation. It must create a new Ada value without mutating the published destination, select
discriminants before final object construction, stage replacement fields transactionally, and clean up after every
format or application failure. Reflection's production `builders` profile currently fails closed, so Serde cannot
derive this direction generically.

This proposal does not add Serde operations to Reflection. It identifies the smallest consumer-neutral construction
capability that a format, configuration loader, test-data builder, or Serde adapter could drive.

## Boundary

Reflection owns:

- whether a source type is structurally constructible through the selected public/private profile;
- generated storage for one unpublished candidate and its child candidates;
- live Ada type and component-declaration capabilities within one generated package;
- exact scalar conversion into the target Ada type;
- discriminant, alternative, component, array-bound, and final aggregate legality;
- candidate cleanup and delivery of one completed typed value.

Serde owns:

- JSON, CBOR, or other format parsing;
- logical type, field, alternative, enumeration, text, byte, and optional presentation;
- aliases, unknown and duplicate policy, defaults policy, missing-field errors, and replacement policy;
- decode limits, logical work accounting, paths, offsets, and destination publication;
- resolving an input presentation to live Reflection component capabilities and scalar operations.

Reflection construction must not import Serde, JSON, CBOR, Type IR, Wire, or a format profile. Serde's root runtime
must not import Reflection. The eventual bridge remains a separate optional consumer crate.

## Identity domains

Reflection references are opaque, live, process-local capabilities owned by one exact generated package. They have
no stable byte encoding, numeric order, persistence, cross-build or post-regeneration equality, schema meaning, or
mapping to a Type IR or Wire identity. A Serde overlay or manifest may persist its own presentation policy and resolve
that policy to a live Reflection reference while operating with the exact generated package; it must never persist a
Reflection reference. A construction graph accepts only canonical capabilities in its generated transitive graph.
That graph may deliberately reuse a predefined or imported capability owned by another generated package; package
origin alone neither accepts nor rejects it. Nonmembers, alternate independently generated capabilities for the same
Ada type, and stale references fail closed. Candidate-local child and alternative tokens are additionally bound to one
nonreused candidate owner/session and become stale when that scope closes.

The three identity domains remain disjoint:

- Reflection live capabilities select generated observation/construction operations in one process;
- Type IR stable declaration IDs identify persisted shared structural facts offline; and
- Wire overlay identities own families, fields, variants, tags, revisions, and compatibility.

No conversion function exists between these domains. A diagnostic parity test may compare overlapping names or
structural facts, but it cannot promote one domain into another or use equality in one as authority in another.

## Proposed capability shape

Names below describe roles, not approved public Ada identifiers.

Reflection should add a construction-only erased view hierarchy parallel to, but distinct from, `Value_View`.
Generated code opens one limited root candidate inside a synchronous callback. The callback may inspect its exact
`Type_Reference`, select one terminal construction facet, and recursively open child candidates. Candidate and child
views, text actuals, callbacks, and candidate-local references are synchronous borrows and may not escape that dynamic
scope. Canonical `Type_Reference` and `Declaration_Reference` values retain their separately documented generated-
package/process lifetime, but they remain nonpersistent live capabilities under the identity rules above.

The root-specific generated operation remains typed at its delivery edge. Conceptually it:

1. creates a fresh unpublished generated candidate;
2. calls one consumer driver with the erased root candidate;
3. checks that the candidate was sealed completely and consistently;
4. calls a root-type-specific receiver exactly once with the completed Ada value; or
5. discards every staged value and calls no receiver.

Consumer exceptions propagate only after generated cleanup. Reported construction failure is a status, not an
exception. Cleanup is nonraising and idempotent. A default, failed, discarded, already delivered, cross-owner,
cross-session, stale, or reentrant candidate use fails closed. Constructibility is queried and validated before the
consumer driver is invoked, so a nonconstructible root causes no format read, child callback, candidate mutation, or
receiver call.

The construction contract has a closed semantic outcome domain before implementation: success; neutral
consumer-discard/no-change; not constructible; invalid or foreign/stale state; invalid scalar or use-site constraint;
predicate false; incomplete candidate; alternative/discriminant mismatch; resource or budget denial; and internal
construction failure. Public Ada literal names remain subject to declaration review, but an implementation may not add
an ambiguous catch-all success-like outcome. A prelatched Serde error prevents construction from starting. The first
primary failure poisons the affected candidate, remains primary through child/root cleanup, and permits only discard.
Cleanup failure is recorded only as secondary diagnostic information and never replaces the primary. Predicate false
is a reported construction outcome; an unexpected exception from user predicate/default code propagates after cleanup
and is not relabeled as malformed input. Every non-success operation preserves its documented caller output and leaves
an unopened parent slot unchanged.

Callback action and Reflection outcome are separate. A normal callback return with `Discard` cleans the root or child,
preserves the prior parent slot, and reports neutral consumer-discard/no-change rather than incomplete/internal failure.
The Serde bridge retains any already-latched parse/policy error as primary. If no external error explains an unexpected
discard, Serde may map the neutral outcome to its own application error.

All Reflection semantic failures and candidate misuse use this one `Construction_Outcome` domain; they do not
raise. Only an exception originating in consumer/application code, task abort, `Storage_Error`, or an implementation
defect may leave through the call, and generated cleanup runs first. Exactly one terminal facet must match the root or
child type before the driver/setter callback; zero or multiple matches are internal construction failure. A
constructible root invokes the driver exactly once. A not-constructible root never invokes it. A successful driver and
seal invoke the receiver exactly once; every earlier non-success invokes it zero times.

The consumer-neutral Reflection seam is legal with an indefinite formal `type Source_Type (<>) is private`; an Ada
2022 spike compiled and delivered both a definite record and an unconstrained discriminated record through the same
generic consumer. The first Serde ordinary-assignment bridge deliberately narrows its own formal to
`type Source_Type is private` because its private staging and final publication use ordinary assignment. The generated
actual has this Ada shape, subject to declaration-level review before names freeze:

```ada
procedure Construct
  (Using         : in out Construction_Driver'Class;
   Authorization : in out Construction_Authorization;
   Receive       : not null access procedure (Item : Source_Type);
   Outcome       : out Construction_Outcome);
```

`Construct` invokes `Receive` synchronously at most once and never retains it. The Serde adapter validates its root
builder state before calling `Construct`; the receiver only assigns the completed value into Serde's unpublished
definite nonlimited candidate. A receiver exception propagates after Reflection cleanup and Serde root rollback. A
receiver has no rejection status in this first slice: a condition that could reject must be checked before delivery.
Limited, controlled, indefinite, or move-only retention requires a different future generated hook.

Delivery occurs only after the Serde driver has parsed and sealed the complete root value and successfully called
`Finish_Document`. A trailing-document failure therefore returns from the driver with a primary error, Reflection
discards its candidate, and `Construct` calls no receiver. The optional Reflection bridge is a complete root adapter;
it must not place `Construct` inside the existing `Deserialization_Adapters.Deserialize_Value` path whose document
finish occurs later. Nested child construction never calls `Finish_Document`. Reflection delivery is still not the
application commit point: the receiver assigns only to Serde's private unpublished candidate, after which the root
transaction performs its nonfailing publication step.

The generated operation is a suitable actual for a generic formal whose `Source_Type` is the exact Ada root type.
This preserves the same consumer pattern as serialization: Serde supplies one generic adapter and each generated
reflection package supplies only its exact `Construct` operation. No per-record Serde traversal is generated.

## Candidate transactions

Opening a child creates a fresh unpublished replacement candidate. The prior parent slot is not changed unless the
child callback returns normally, explicitly returns `Accept` after its input is complete, the child seals successfully,
and the parent accepts it. The callback action is initialized to `Discard`, so a setter followed by a later parse error
cannot accidentally commit. Exception, explicit discard, unsealed child, or parent rejection discards the replacement
and preserves the prior slot before status return or exception propagation. No retry occurs after root delivery. This
is required for keep-last duplicate policy and for resource-owning future adapters.

Valid recursion opens one descendant child while its parent is in a suspended-child state. The consumer may recurse
through that child, but it cannot mutate the parent, open a sibling, reuse the same child, or reenter either candidate
until the child seals or discards and the parent resumes. The owner/session state machine is explicitly
fresh, active, child-suspended, sealed, discarded, and delivered; only the documented forward transitions are legal.
Each operation checks the creating task as well as the owner/session. Candidate handoff to another task, concurrent
use, same-candidate reentry, sibling use while suspended, and stale use fail before mutation. A controlled local root
guard discards partial state during exception or task-abort unwinding; an exception handler alone is not cleanup
evidence.

Component selection uses `Declaration_Reference`, never spelling. Presentation names remain observations for schema
and diagnostics. Serde resolves its own primary names and aliases to one declaration before opening a child.
Reflection rejects a declaration that is not a component of that candidate or is inactive under the selected
alternative.

The bridge is an independent dynamic construction traversal; the existing compile-time ordinal
`Adapters.Records` and `Adapters.Variants` instances cannot implement it directly. Before input traversal, the root
candidate exposes a bounded synchronous inventory:

- an exact component count and one callback per component in declaration order;
- each component's live capability, declared name, role, required/default availability, and alternative membership;
- an exact alternative/path count and one callback per candidate-local alternative capability;
- each alternative's immediate diagnostic choice text and component membership; and
- exact applicability queries after one alternative is selected.

Names have arbitrary Ada bounds and callback lifetime. The bridge copies them only after checking caller-supplied
maximum component, alternative, and UTF-8 byte limits. It resolves its initial presentation policy by bounded name
matching and stores only operation-local live capabilities. Aliases require a separate Serde overlay actual and are
resolved to the same live component within that scope. Unknown text, ambiguous matching, duplicate capabilities,
foreign references, count drift, callback drift, or membership inconsistency rejects before candidate mutation.

Missing/default policy stays outside Reflection. A generated candidate may expose an operation that records a
`Use_Declared_Default` marker for an empty component slot, but it must not evaluate the expression immediately. If the
generator can reproduce the exact source default at seal, the final named aggregate uses `<>`, so Ada evaluates the
source expression exactly once with the completed discriminants and proper context. This is an Ada construction
action, not a Serde schema default or Wire compatibility default. Generated code identifies the exact component,
source default, and compiled-body provenance; Serde overlay policy alone decides whether a missing input field records
the marker. Defaults that cannot be reproduced this way are not advertised. An exception from evaluation discards the
candidate and propagates after cleanup. The first construction slice omits defaults entirely, so every required
component must have a completed slot before the root can seal.

## Construction resources and accounting

"Definite" and "statically constrained" do not by themselves establish an acceptable construction resource bound.
Before generated code creates root storage, Reflection must expose a nonmutating eligibility/resource preflight for the
exact candidate graph. The initial bounded route is admitted only when generated-target compilation proves a fixed
upper bound for root and child candidate storage, no hidden heap allocation, and no unbounded secondary-stack use.
Serde supplies explicit caller limits and authorizes that bound before the candidate or first child exists. A type for
which the generator cannot prove these conditions is allocating/unbounded and is not supported by the initial bridge.

Successful preflight mints one private limited, task-bound `Construction_Authorization` for the exact root/use-site,
transitive graph, caller ledger/session, limits, and cost-model version. The authorization is passed explicitly to
`Construct`, as shown above; it is single-use, has no caller constructor, and cannot be rebound to a fresh session.
Before any allocation or mutable candidate access, `Construct` atomically validates and consumes that authorization.
Mismatch, reuse, denial, or stale/foreign task/session fails before storage. The same exact session is available through
the driver for every child charge; a nested ledger or reauthorization cannot bypass the root reservation.

Construction work and candidate slots use one explicit caller-owned Reflection-operation ledger/session. There is no
default limit, reset, replenishment, or refund. The generated operation charges before work or candidate storage, and
an accepted charge remains consumed after later failure. Cleanup/finalization is nonraising, ledger-free, and preserves
the first primary failure. Serde's logical `Decode_Budget` continues to own input units, logical values, containers,
text/byte limits, and paths; it neither duplicates nor satisfies Reflection's construction-storage/work charges. The
cost model, charge order, denial preservation, and exact candidate-storage unit require a separate declaration review
before an implementation claims bounded operation.

Task exclusion must be mechanical, not merely documentary. The declaration/implementation review will choose either
an immutable authorization/candidate identity gate read before any mutable component or a protected session gate, and
concurrent foreign-task tests must prove rejection before mutation.

## Scalars

Construction facets must be total over their advertised capability and must never narrow, round, use `Image`, or
infer from a diagnostic name.

- Boolean accepts a Boolean value.
- Signed and modular integer candidates may accept canonical arbitrary-bound decimal text under the grammar already
  exposed by value views, but Serde's current format-neutral pull API supplies only exact `Integer_64` and
  `Unsigned_64` values. The first bridge maps those two event domains through setters that are total and exact for
  every event: a target accepts each individually representable value and returns invalid-scalar/out-of-range without
  mutation for every other value. Generated code performs exact base-type conversion and
  then validates the exact component or discriminant use-site subtype and every supported constraint before parent-
  slot acceptance. Predicate-bearing use sites are excluded from the first slice because evaluation followed by
  assignment or final aggregate construction can reevaluate an impure predicate and is not a proven no-fail swap.
  Grammar, range, or constraint failure leaves the slot unchanged. Wider construction requires a separately reviewed format-neutral big-integer
  event/capability; the bridge never asks JSON or CBOR for a private number lexeme.
- Enumeration accepts one canonical live `Enumeration_Literal_Reference`. Diagnostic spelling and declared position
  are observations, never the semantic setter input. Serde resolves presentation names and aliases to that capability
  before opening or setting the child; stale, wrong-type, and capabilities outside the generated transitive graph fail
  closed. A canonical imported literal capability in that graph remains valid regardless of owning package.
- Character accepts an exact Ada position and separately validates any Unicode-scalar mapping selected by Serde.
- Floating and fixed candidates may eventually accept the exact rational/model facts of the common facets. The
  current pull API supplies only `Float_64_Value`, so a future setter must decide each event exactly and totally,
  including classification, rational value, signed zero, and nonfinite policy. It accepts an event only when that
  event maps exactly and otherwise returns invalid-scalar without mutation. A type is not constructible only when the
  implementation cannot make this decision exactly and totally for the type.
  Arbitrary rational construction requires a future format-neutral capability and never reaches into a backend.

Arbitrary-bound text actuals are synchronous and nonretained. Allocating String-returning observation APIs are not a
bounded construction channel; a bounded bridge needs caller-buffer or callback forms before claiming bounded scalar
construction.

## Records and variants

A record candidate exposes all structurally constructible declarations needed to build the value, not merely the
components active in a previously observed object. Discriminants, ordinary components, and variant components retain
their distinct roles and declaration identities.

For a discriminated record, generated storage stages discriminant values before constructing the final Ada object.
The first slice permits arbitrary serialized field order only when every child subtype and constraint is independent
of discriminant values. A nonvariant discriminated record in that slice can accept its discriminant after an
independent field and still construct only at seal. A component such as `String (1 .. N)` cannot open before `N` is
staged; it remains nonconstructible until a reviewed protocol either requires shape-defining discriminants first or
provides bounded raw-value staging and replay.

This can produce an unconstrained discriminated aggregate and lend it synchronously to a typed receiver, but the first
Serde ordinary-assignment bridge cannot retain that value. Serde publication requires either a definite/constrained
root seam, a caller-supplied destination whose discriminants are checked before assignment, or an explicitly authorized
indefinite holder/allocator. Callback-only construction tests do not imply application publication support.

For a variant record, Reflection supplies a private candidate-local alternative capability bound to one exact variant
part/path in the generated graph. A variant alternative or choice path is not treated as a named Ada declaration.
The capability has no stable encoding, ordering, persistence, or schema meaning. Serde selects it before opening
variant-owned child slots, and the candidate still receives every required discriminant explicitly. At seal,
generated code applies Ada choice semantics and proves that those discriminants select the asserted path, that only
its components are present, and that every required active component is complete. The token is only a fail-closed
construction assertion; it is not a Wire tag, Type IR alternative ID, or inferred discriminant. An `others`
alternative never invents a discriminant value from its choice text. Discriminant-dependent child shapes have the
same first-slice restriction as nonvariant records.

Reflection does not buffer format input. Before a branch-owned component can open, the adapter must have resolved and
selected the exact candidate-local alternative. Serde may require an envelope order or perform explicitly bounded
staging/replay when its representation permits branch fields before that selection. "Arbitrary field order" applies
only after these shape prerequisites are established; it is not a Reflection buffering promise.

The first construction slice may support only the already reviewed untagged nonvariant and flat-variant graphs.
Nested variants require the same rules at every path. Tagged types, extensions, interfaces, access graphs, tasks,
protected objects, and predicate/invariant-bearing or private types without explicit constructor authority remain
nonconstructible. A representation clause alone does not make a type nonconstructible when exact value conversion and
named aggregate construction remain legal; it also contributes no serialization identity or ordering.

## Arrays and resource policy

Array construction cannot infer Ada bounds from a sequence length. Constructibility is use-site-specific: a constrained
component such as `Fixed_Row (1 .. 2)` owns a component candidate specialized to those bounds while retaining the
canonical unconstrained array type's `Type_Reference`. A generic candidate for that unconstrained canonical type remains
not constructible. A constrained subtype root needs its own nameable generated `Construct` seam or is excluded. For
each admitted definite constraint, Reflection owns and exposes the exact source bounds, cardinality, and Ada component
order; Serde only verifies that the decoded representation has that cardinality. The overlay cannot supply or override
those structural facts.
Runtime bounds or a previously established destination shape are consumer policy only for a future unconstrained
construction protocol. JSON/CBOR length, declaration position, and Wire layout never imply an Ada lower bound or
dimension shape.

The initial bounded slice may support definite constrained arrays only after the pre-candidate storage/work gate above
authorizes the exact full candidate. Null arrays are valid; dimension cardinality and product are checked without
overflow before the first element opens. Unconstrained roots, runtime-sized components, and multidimensional shapes remain
nonconstructible until Reflection has a reviewed caller-authorized storage protocol. Such a protocol must request
resource permission before dynamic storage, expose no default capacity or allocator, and retain the same scoped
candidate and cleanup rules. It must not silently use the standard heap or an unbounded secondary stack.

Elements are addressed in Ada component order and opened as transactional child candidates. Exact cardinality is
checked before seal. Serde's format-level sequence representation remains independent of the Ada lower bounds.

## Publication and ownership

Reflection delivers a completed typed value only inside the root receiver callback. That callback may copy or move it
into Serde's private root builder according to the exact type's authorized ownership contract. Serde's existing root
transaction calls `Finish_Document` before publishing and rolls back after every status or exception. Reflection
delivery therefore does not itself publish an application value. The receiver value is a synchronous borrow valid only
for that call. Reflection invokes it exactly once only after successful final aggregate creation, never retries it, and
cannot roll back arbitrary mutation performed inside it. Consequently the first Serde receiver mutates only a private
rollback-capable builder. Receiver exception triggers generated cleanup, propagates, and results in no application
publication.

The task-abort guarantee is deliberately narrow across this boundary. Reflection's controlled guard always discards
its active graph. After the receiver runs, the first Serde bridge may contain only an ordinary definite,
nonlimited/noncontrolled value with no access graph, owned resource, active child, or public readiness token. Abort in
the remaining prepublication interval leaves at most inaccessible inert bytes; it cannot publish them, and the next
`Begin` overwrites them before reuse. Supporting a builder that can retain active/resource state instead requires a
Serde-side controlled transaction guard whose finalization performs nonraising rollback.

The initial generic bridge may accept only definite nonlimited, noncontrolled types whose final transfer is ordinary
assignment and whose candidate resource proof satisfies the bounded gate. Limited, controlled, move-only, private, or
resource-owning types require an explicit generated or handwritten
constructor/transfer hook. Visibility alone never grants that authority. `Not_Constructible` must carry an exact
consumer-neutral reason before Serde reads input or mutates a candidate.

That reason domain is closed for the first API version: unsupported type category; unavailable representation
visibility or constructor authority; limited/controlled/resource/invariant/predicate-bearing semantics; indefinite
retention; unconstrained or unsupported use site; shape prerequisite/dependent constraint unsupported; imprecise
semantic resolution; exact scalar decision unavailable; and bounded resource proof unavailable. Resource denial after
a supported preflight is a construction outcome, not a not-constructible reason. Unknown future reason text never
defaults into one of these cases.

An indefinite root may use the consumer-neutral Reflection callback seam, but it is not accepted by the initial Serde
ordinary-assignment bridge. Accepted-replacement cleanup for limited, controlled, and resource-owning values is future
work; successful ordinary assignment in this slice is not evidence for such a handoff.

## Required evidence before implementation freezes

1. The existing Ada 2022 legality spike must become a maintained compiling/running test for the exact erased-candidate
   plus typed-root callback and generic-formal declarations. It must cover definite and indefinite root delivery,
   callback exception behavior and accessibility, plus negative retention and mismatched-root cases. Only the definite
   root is admitted to the initial Serde ordinary-assignment bridge.
2. Generated fixtures must cover Boolean, signed, modular, enumeration, a constrained array component, a simple
   record, a nonvariant discriminated record, and both paths of a flat variant.
3. Every definite fixture admitted by the Serde bridge must deserialize through both installed JSON and CBOR into a
   private Serde candidate, including missing/unknown/duplicate policy, replacement failure, alternative/discriminant
   mismatch, malformed and out-of-range scalars, truncated/trailing input, and successful reset/reuse. Field-order
   tests must distinguish shape prerequisites from ordinary components; branch fields are not admitted before exact
   alternative selection unless Serde provides reviewed bounded staging.
4. Construction, parse, policy, and trailing-document failures must call no receiver. An accepted child transfers its
   staged value into the parent exactly once and relinquishes child ownership; every unaccepted opened child is
   discarded exactly once. Receiver, scalar, future predicate/default, callback exception, and task-abort paths retain
   the primary failure and perform every applicable cleanup before propagation.
5. Lifecycle tests must cover foreign owner/session/task, stale reference, nested valid recursion, forbidden reentry,
   double seal/discard/delivery, regenerated identities, independently generated packages for the same Ada type, and
   accepted canonical predefined/imported capabilities from the generated transitive graph. Child tests cover
   unsealed, sealed-then-discarded, accepted ownership transfer, parent rejection, and duplicate replacement failure.
   Variant evidence includes choice lists/ranges, `others`, foreign alternatives, source
   reordering, discriminant duplicates/replacement, dependent-constraint rejection, and nested paths before those
   paths are admitted.
6. Resource evidence must cover null arrays, exact dimension-product overflow, a large fixed candidate denied before
   root storage or the first child, exact charge traces and denial boundaries, no hidden heap/secondary-stack use, and
   nonraising ledger-free finalization. A task abort after receiver assignment must leave the application destination
   unchanged, expose no readiness token or active resource, and permit the next `Begin` to overwrite the inert candidate.
7. Negative compile tests must reject mismatched root types and construction operations. Installed-client tests must
   compile, link, and run without checkout, Git, path, Libadalang, Type IR, or generator dependencies.
8. Serialization and deserialization may resolve to the same live Reflection declaration/type capabilities but share
   no mutable candidate state. Tests must prove that no Reflection, Type IR, or Wire identity converts into another.
   Existing JSON/CBOR encodings and handwritten adapter behavior must remain byte-for-byte unchanged.
9. Direct Reflection generation remains fixture/development-only until reviewed evidence establishes exact project,
   scenario, target, runtime, and compiler-switch identity; same-invocation GNAT legality; complete admitted generic,
   private, and variant semantics; deterministic fail-closed diagnostics; source-snapshot/provenance attestation; a
   reviewed indexed Reflection release; and installed dependency isolation. A construction fixture or API cannot mint
   production authority, and persisted Reflection metadata remains non-authoritative.
10. Architecture, implementation, fix, and final independent reviews must close P0/P1 and normally P2 before any
   public Reflection or Serde construction API freezes.

## Explicit non-goals

This proposal does not define stable schema IDs, wire tags, compatibility, access-graph identity/cycles, allocator
selection, source-extraction authority, private representation authority, or generated constructor annotations. It
does not make persisted Type IR or Reflection metadata a production construction capability.
