# Generic Reflection integration proposal

Status: architecture frozen for implementation; no dependency or public API is released by this document.

## Problem

The Serde runtime and its JSON and CBOR backends work with handwritten adapters and generated fixtures. The installed
Ada generator still fails closed because neither the Type IR production capability nor a complete production source
frontend is published. Requiring a Serde-specific mode in Flyology Reflection would duplicate structural traversal,
couple a consumer-neutral project to Serde policy, and prevent other consumers from using the same generated views.

Flyology Reflection now exposes consumer-neutral typed observation. A generated package supplies exact root `Observe`
operations; every routed value has one terminal scalar or structural facet; arrays and records synchronously route
borrowed child views; variants report their selected structural alternative; and process-local type and declaration
references preserve graph identity. Serde can consume that contract generically. Reflection must not own a `Serialize`
operation or emit Serde code for this route.

## Crate and dependency boundary

Add a separate optional Alire crate, `flyology_serde_reflection`, with Ada root `Flyology_Serde_Reflection`. It depends
on indexed releases of `flyology_serde` and `flyology_reflection`. It is not part of the root `flyology_serde` project,
and the root runtime keeps no Reflection, Libadalang, Type IR, process, or generator dependency. The integration crate
contains no Libadalang and consumes only Reflection's installed Ada observation API.

No Git or path pin is accepted in a committed manifest or supported test path. Until a reviewed
`flyology_reflection=0.1.0-dev` is resolvable through the Flyology Alire index, implementation may be exercised only
as an uninstalled experiment and cannot be described as a released integration. A movable `-dev` version is not
snapshot identity: every freeze records the exact Reflection source commit, exact Alire-index commit, and resolved
solution lock, and reruns every gate if that index entry moves.

The initial public unit is a generic root adapter:

```ada
generic
   type Source_Type (<>) is limited private;
   Limits : Flyology_Serde.Serialization.Serialization_Limits;
   with procedure Observe
     (Item  : Source_Type;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);
package Flyology_Serde_Reflection.Serialization_Adapters is
   procedure Serialize
     (Item  : Source_Type;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info);
end Flyology_Serde_Reflection.Serialization_Adapters;
```

The declaration above has compiled with scalar, record, variant, and indefinite-array actuals; its final names remain
subject to API review. A caller instantiates it with the generated source package's canonical `Observe`; it does not
pass an ordinary package as metadata and does not register source types globally. The implementation reuses
`Flyology_Serde.Serialization_Adapters` so the Reflection traversal is validated first against Serde's counting
serializer and stable backend capabilities, then repeated against the real backend. The caller must externally
exclude mutation or serialize a stable snapshot. The generated `Observe`, all child observations, type identities,
names, scalar values, and callback order must be stable and side-effect-free across both passes. Supplying a
signature-compatible procedure is contractual and is not proof that it came from reviewed generation.

## Initial lossless mapping

The integration owns the mapping from Reflection's consumer-neutral facts to Serde's logical data model:

| Reflection facet | Serde event mapping |
| --- | --- |
| `Boolean_View` | `Put_Boolean` |
| `Signed_Integer_View` | exact checked canonical-decimal conversion followed by `Put_Signed` |
| `Modular_Integer_View` | exact checked canonical-decimal conversion followed by `Put_Unsigned` |
| `Enumeration_View` | `Put_Enumeration`, using the reflected qualified type name and declared literal spelling |
| supported `Array_View` | one known-length `Begin_Sequence`, reflected element order, `End_Sequence` |
| nonvariant `Record_View` | `Begin_Record`, every reflected component in callback order, `End_Record` |
| `Record_View` plus `Variant_View` | one `Begin_Variant` for the selected structural alternative, every active reflected component, `End_Variant` |

The generic variant mapping includes reflected discriminant components in the payload. An `others` alternative may
cover several discriminant values, so the branch name alone cannot reconstruct the Ada value. Keeping the active
discriminant is the lossless default; a future overlay-specific generated adapter may omit a discriminant only after
proving that its selected constructor uniquely determines the value.

The initial exact array mapping accepts only rank-one values whose bound views have the canonical process-local
`Standard.Integer` identity and whose exact bounds are `1 .. Length`, or `1 .. 0` for an empty value. It observes and
validates both bounds before `Begin_Sequence`; every other bound, index scalar, rank, unrepresentable cardinality, or
malformed bound callback returns `Unsupported_Value` or
`Application_Error` under the failure table below before real output. Flattening a multidimensional array or erasing
an arbitrary lower bound would be lossy, so those values remain unsupported until a reviewed shape envelope or
builder policy preserves rank, every dimension, and every actual bound. A future statically rendered adapter may
prove bounds from its exact destination subtype instead; the generic adapter does not infer that proof.

Signed and modular canonical text is validated before Ada conversion. Signed text is exactly `0` or `-` followed by
a nonzero decimal digit and zero or more digits; modular text is `0` or a nonzero digit followed by zero or more
digits. The adapter compares canonical lengths and digits against the exact decimal endpoints before calling
`Integer_64'Value` or `Unsigned_64'Value`. Malformed canonical text is `Application_Error`; well-formed values outside
Serde's exact 64-bit logical scalar families are `Unsupported_Value`; conversion `Constraint_Error` after a proved
in-range value is `Application_Error`. No scalar event occurs before all checks succeed. Allocation failure while
Reflection produces a String, or any other unexpected exception, follows the root exception/abort contract rather
than being mislabeled as a value error.

Floating, fixed, character, unsupported, malformed, count-not-representable, and access-graph views also fail before
real output until an explicit lossless mapping is reviewed. In particular, a `Character_View` is not silently
interpreted as text or a byte merely because its position is available.

`Qualified_Name (Type_Of (View))`, component names, literal names, and selected choice names are presentation text,
not persistent schema identities. The adapter retains no `Type_Reference` or `Declaration_Reference`. It immediately
uses `Same_Type` only to require canonical `Standard.Integer` array bounds; every other identity and presentation fact
must remain stable across both passes as a generated-observer precondition. A later registry-based policy must use
`Same_Type` or `Same_Declaration` and exact-family membership, never names.
The integration derives no Wire family ID, field or variant tag, schema fingerprint or revision, compatibility
policy, canonical wire ordering, or physical representation fact.

## Traversal, ownership, and failure contract

The adapter uses stack-local limited consumers whose nested primitive bodies close over the current serializer,
error, counts, and path. It uses neither `Unchecked_Access` nor a library-level access field. It recursively consumes
child views only during the Reflection callback that supplies them and retains no view, child access, input range,
borrowed name, type reference, declaration reference, consumer, serializer access, or error access after the
synchronous call returns. Reflection's canonical root and child views remain the only borrow owners. A callback may
validate and copy semantic text into operation-local owned storage; that copy carries no access to the borrowed
String and is discarded before the enclosing traversal returns.

Before each structural begin event the adapter validates the terminal facet and exact preamble. A `Variant_View` is
legal only together with `Record_View`; scalar, enumeration, array, or unsupported terminal facets supplemented by
`Variant_View` are malformed and reject before a scalar or container event. Cardinalities convert to `Natural` only
after an explicit range check. A variant must announce exactly one selected alternative. Its observer first runs
transactionally with no Serde event: the sole callback validates the arbitrary-bound choice name, requires valid
UTF-8 and length at most `Limits.Maximum_Text_Length`, and copies it into fixed operation-local storage whose bound
is the generic limit. The copy allocates nothing. A zero or second callback is `Application_Error`; overlength is
`Capacity_Exceeded`; invalid UTF-8 is `Invalid_Text`. Only after the observer returns successfully with exactly one
callback does the adapter push the owned alternative name and call `Begin_Variant`. The alternative path remains
through successful `End_Variant`, after which the owned name is discarded.

The legal event and path grammar is exact:

- an array performs `Begin_Sequence`; for each zero-based logical position it pushes the index, recursively emits
  exactly one child, and pops only after success; it then performs `End_Sequence`;
- a record performs `Begin_Record`; for each reflected component it pushes the field, performs `Put_Field`,
  recursively emits exactly one child, and pops only after success; it then performs `End_Record`;
- a variant pushes the selected alternative, performs `Begin_Variant` with `Active_Component_Count`, then emits each
  discriminant, common, and active variant component using the same field grammar, performs `End_Variant`, and pops
  the alternative only after success.

Ordinary status failures retain the failing index/field/alternative path. Only the root adapter's unexpected-exception
handler clears the path after aborting. Extra callbacks are rejected before increment or output; zero callbacks,
wrong counts, multiple selected alternatives, or a callback after a latched error are protocol failures. Component
roles do not change field order.

Reflection failures use this closed precedence before a later serializer state error can obscure them:

| Reflection result | Serde result |
| --- | --- |
| `Unsupported_View`, supported facet with an unrepresentable exact scalar, `Count_Not_Representable`, or an unsupported exact array shape | `Unsupported_Value` |
| malformed terminal/supplemental facets, malformed canonical scalar text, inconsistent preamble, invalid bound callback, zero/extra callbacks, count drift, selected-alternative drift, or `Traversal_Not_Available` after an advertised exact preamble | `Application_Error` |
| selected alternative text longer than the configured text limit or invalid UTF-8 | `Capacity_Exceeded` or `Invalid_Text`, respectively |
| destination capability, capacity, depth, state, text, or sink failure | the first existing backend/Counting error |
| unexpected exception, including `Storage_Error` from allocating Reflection observations | abort both passes, clear the path, and propagate |

A callback exception immediately stops traversal and no later callback is accepted. Unexpected exceptions propagate
through the root Serde adapter only after both the counting serializer and destination have been aborted. No failed
operation can publish a successful document; buffered JSON/CBOR expose no candidate. A streaming sink may already
have accepted bytes that Abort cannot retract, so its caller must discard the failed operation's stream segment.

Serde owns logical depth, container-item, text/name length, byte length, and event charging through the counting and
backend passes. Reflection owns its observation work and any allocation performed by its current String-returning
scalar API. The initial integration is therefore not a bounded-memory adapter. It must say so explicitly and must
not double-charge Serde logical events for Reflection-only preambles, selected-alternative observations, or callback
dispatch.

## Deserialization and construction

This milestone is serialization-only. Observation cannot construct an Ada value. Generic deserialization becomes
eligible only after Reflection publishes a separately reviewed builders profile with:

- an unpublished candidate owner distinct from the observed value;
- exact alternative/discriminant construction and component membership;
- bounded or explicitly allocating field storage;
- private, limited, controlled, and invariant-bearing authorization;
- commit as the only publication operation; and
- nonraising abort/reset that releases every resource after every failure.

Serde will then provide a separate generic deserialization adapter. It will not cast an observation view into a
builder, mutate a published value incrementally, or infer a constructor from names.

## Relationship to static generation and Type IR

This integration is an optional runtime bridge. It does not replace the Serde-private lowered graph and renderer,
which produce standalone adapters that depend only on `flyology_serde`. It also does not replace the shared offline
Type IR/extractor route. The three supported strategies have distinct dependency and authority properties:

1. handwritten or combinator adapters depend only on the root runtime;
2. the generic Reflection adapter depends at runtime on Serde and Reflection observation packages; and
3. statically rendered adapters consume a checked source or Type IR frontend offline and depend only on Serde at
   runtime.

Persisted Type IR JSON never becomes production extraction authority. Reflection views never become a Type IR
document or Wire input. The same fixture may traverse both frontends to detect disagreement, but neither silently
overrides the other.

## Evidence and freeze gates

Before the serialization integration may freeze:

1. Reflection must publish a reviewed indexed `-dev` release with the exact observation units used here and no
   downstream Git/path pin; the evidence records and attests its exact source/index commits and solution lock.
2. The integration crate must build independently without entering the root runtime's source or ALI closure.
3. A generated reflected fixture must serialize Boolean, signed, modular, enum, accepted canonical rank-one arrays,
   nonvariant records, discriminated records, and a flat `others` variant through JSON and CBOR. Arbitrary-bound and
   multidimensional values must reject before destination mutation.
4. JSON and CBOR results must match the equivalent handwritten/static Serde traversal byte-for-byte where the logical
   mapping is the same.
5. Tests must cover canonical and malformed scalar lexemes, exact/one-past scalar ranges, canonical and rejected
   empty/null/arbitrary-bound/multidimensional arrays, oversized cardinality, malformed terminal-plus-variant and
   unsupported facets, callback-count overflow/drift, zero/multiple selected alternatives, nested failure paths,
   alternative names at the configured maximum and one past it with arbitrary bounds, fixed-storage copying,
   prelatched errors, prepoisoned writers, counting-pass rejection with untouched destination, callback exceptions,
   no callback after failure, streaming-abort wording, and reset recovery.
6. External compile tests must cover scalar, unconstrained-array, and limited roots; overloaded `Observe` resolution;
   a rejected mismatched `Observe`; arbitrary String bounds; recursive callback exceptions; and installed-client
   compile/link/run.
7. Source, ALI, object, archive, installed-file, and dependency-closure scans must prove no Reflection or Libadalang
   dependency enters the root Serde source/ALI closure or a statically generated adapter, and no Libadalang or Type IR
   dependency enters the integration crate itself.
8. Architecture, implementation, fix, and final independent reviews must report P0/P1 and normally P2 closed.

## Review record

The earlier Wire boundary review reported P0/P1 none provided Reflection remains consumer-neutral, Type IR remains the
shared offline structural interchange, Wire policy is never inferred, and direct Reflection use stays nonproduction
until its own authority gates are reviewed. This revision removes the earlier Serde-specific Reflection backend and
instead proposes a separate generic consumer crate.

Architecture review cycle one reported P0 none, four shared P1 themes, and P2 evidence/wording findings. Corrections
now reject lossy array shapes; close scalar grammar/range, event/path, malformed-variant, failure, exception, streaming,
borrow, source-stability, dependency, and exact movable-release contracts; and add the external compile and adversarial
evidence matrix. Fix review found one remaining P1 in selected-alternative callback timing and a P2 claim about
unobservable cross-pass identity drift. The final design transactionally copies exactly one validated alternative
name before any Serde event and makes identity/name/order stability a caller/generated-observer precondition.

Both independent final architecture reviewers report P0/P1/P2 none. The proposal is frozen for implementation, but
implementation and release remain gated on the exact reviewed indexed Reflection snapshot and the change/fix/final
review cycles above.

The final uninstalled-checkpoint change and safety reviews also report P0/P1/P2 none. Their independent reruns used
the exact archived Reflection source and fresh build/output directories. The last fix cycle added zero-limit
lifecycle, hostile array-bound and callback protocols, retained variant error paths, direct handwritten JSON/CBOR
parity, and experiment-local build-artifact exclusion. Indexed and installed evidence remains a promotion gate, not a
claim of this checkpoint.

## Uninstalled implementation checkpoint

The repository now contains `experiments/reflection_serialization`, an uninstalled implementation against exact
Reflection commit `9d3c9b17c8bb510ddfdf8a286e5a192ff929640b`. Its runner exports that commit into a fresh temporary source tree,
builds Reflection there, builds and runs the integration in fresh temporary object and executable directories, and
checks that Reflection or extractor dependencies do not enter the root Serde source/build closure. The maintained
tests cover successful Boolean, enum, signed, modular, canonical rank-one array, record, discriminated-record, and
flat-variant JSON/CBOR traversal; direct byte parity with equivalent handwritten record/array and variant traversals;
unsupported/lossy shapes; scalar range and grammar; limits; paths; reset; record, array-element, and array-bound
callback count drift; array rank, count-product, bound-terminal, supplemental-facet, identity, canonical-text, and
range failures; fixed-storage alternative names at and beyond the exact limit, including a zero text limit; retained
alternative and field paths after a child failure; Reflection protocol failures; and first- and second-pass exception
cleanup.

The final implementation, attestation, change, and safety reviews report P0/P1/P2 none for this checkpoint. This is
not the crate release or API freeze. Before promotion, the remaining P2 gates are a reviewed indexed Reflection
release, a rejected mismatched-`Observe` external compile test, installed-client compile/link/run, and full installed
dependency-closure isolation tests. Generic deserialization remains blocked on reviewed Reflection builders and is
not implied by this serialization checkpoint.
