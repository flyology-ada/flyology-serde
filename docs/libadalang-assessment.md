# Libadalang derivation-front-end assessment

Decision: Libadalang 26.0.0 is the appropriate parsing and semantic-resolution foundation for the shared offline
extractor, but it is not a compiler, schema language, or serde policy engine. The extractor pins that version,
requires a successful GNAT legality check for the same project configuration, and rejects every imprecise result on
a mandatory path.

The [Libadalang project](https://github.com/AdaCore/libadalang) describes its core services as complete Ada 2022
syntax, reference and type resolution, and cross-reference queries. It also explicitly says that it does not provide
full Ada legality checking. The [Libadalang 26 release notes](https://docs.adacore.com/live/wave/libadalang-release-notes/html/libadaland_release_note/libadalang_26.html)
add precision-bearing failsafe reference results, static-constraint queries, target-aware Standard types, and
improved resolution in generic code. Those boundaries match an extractor that fails closed; they do not justify
using Libadalang results without compiler and fixture checks.

## Project identity is part of the query

Name and type resolution depend on the selected source closure, scenario variables, target, and runtime. The
[project-provider documentation](https://docs.adacore.com/live/wave/libadalang/html/libadalang_ug/ada_api_tutorial.html)
shows that a GPR2 project tree supplies units and runtime sources to an analysis context. One extraction transaction
therefore records and uses:

- the canonical GPR path and requested root units;
- a sorted scenario-variable map;
- exact target, runtime, GNAT, Libadalang, and extractor identities; and
- a deterministic manifest and digest of the effective source closure and relevant configuration inputs, including
  selected units, configuration pragmas, runtime sources, and effective compiler switches.

The digest is provenance, not declaration identity. It ensures that identical tuple text cannot disguise changed
project or runtime contents. The normative manifest shape belongs to the versioned Type IR contract rather than the
serde overlay.

GNAT legality and extraction run in one invocation against that tuple. A previous successful build is not evidence.
Missing units, a different runtime, an imprecise failsafe resolution, a property exception, or a syntax diagnostic
on a mandatory declaration stops extraction.

## Facts the extractor can obtain

After those gates, the extractor can rely on the precise syntax tree for declaration form and source order, and on
successful semantic properties for resolved identity. The supported v1 fixture matrix covers:

| Ada construct | Extracted evidence | Fail-closed qualification |
| --- | --- | --- |
| Signed, modular, floating, ordinary fixed, decimal fixed, enumeration, and character types | Declaration kind, base/root/subtype links, literal order, and explicit constraint syntax | Static values are Known only after target-aware exact evaluation; otherwise the constraint fact is Unknown or Unsupported |
| Derived types and subtypes | Resolved parent/base/root declaration plus the subtype indication and use-site constraints | Never collapse a subtype into its base type when its constraint, predicate, or view changes consumer behavior |
| Arrays | Rank, component type, each index subtype, and exact bound syntax | Static and dynamic bounds remain distinct; anonymous array types are rejected instead of receiving location-derived IDs |
| Records and record extensions | Tagged/limited/abstract facts, parent type, discriminants, components, defaults, and declaration order | Controlled status and inherited components must be resolved explicitly; a missing mandatory fact is not treated as false |
| Discriminated records | Exact nested variant-part, alternative, choice, component, and selector AST | Walk the actual AST; `p_shapes` is diagnostic-only because a summarized shape is not a lossless variant condition |
| Access, interface, class-wide, task, and protected types | Declaration form, designated/base type where applicable, and semantic category | Serde generation rejects these by default; extraction does not imply a safe value mapping |
| Private and incomplete views | Public/private/full declaration identities and completion links | Full-view discovery is separate from authorization to expose or name the full view |
| Aspect specifications, pragmas, predicates, and representation clauses | Exact syntax and resolved associated entity where the property is precise | Physical representation is recorded only as ignored provenance when needed; semantic predicates remain explicit facts and are not guessed |

Libadalang exposes syntax fields such as `f_aspects` and semantic properties including designated type declarations,
base/root types, private completions, discriminants, and static constraints. The generated API index documents those
queries, while the extractor fixtures establish which 26.0.0 combinations are accepted. API availability alone is
not a promise that every property call is precise for every program.

## Generics

Libadalang can identify a generic instantiation, its designated generic declaration, and the instantiation chain.
Its [generic-actual example](https://docs.adacore.com/live/wave/libadalang/html/libadalang_ug/examples/generic_instantiation.html)
also demonstrates that a type expression inside the generic can resolve to its instantiated actual.

The extractor still owns an explicit formal-to-actual map. It walks positional, named, defaulted, boxed, and nested
associations and distinguishes type, object/value, package, and subprogram formals. Values that affect bounds,
discriminants, or representation-independent type shape are retained exactly or marked Unknown/Unsupported.
Remaining formals are not silently represented as their generic declaration. Each supported pattern has a fixture;
anything outside the tested matrix fails strict extraction.

## Aspects, representation, and annotations

Physical `Size`, alignment, packing, convention, bit/component, storage-order, and enumeration representation
clauses do not control serde encoding. The extractor may locate them for diagnostics but does not lower them into
logical events. Enumeration declaration order, not representation value, is the default serde literal order.

Semantic aspects such as predicates, invariants, defaults, and class-wide/tagged properties can affect whether a
candidate is valid. They remain structural facts, with Known/Unknown/Unsupported status, for the generator or a
handwritten construction hook to handle. The extractor does not execute arbitrary user validation code.

GNAT `Annotate` pragmas/aspects can be harvested as optional source-local metadata when the associated entity is
precise. The authoritative serde overlay is nevertheless a versioned companion document keyed by Type IR semantic
ID. It is needed for:

- serialized names and accepted aliases;
- skip, required, optional, missing, and default presentation rules;
- text/byte encoding and array-bound representation;
- numeric exactness adapters and format capability requirements;
- private observers, constructors, transactional commit/rollback hooks, and controlled-resource policy;
- bounded capacities, allocation policy, and unknown/duplicate-field behavior; and
- requests to use a generic combinator or a handwritten adapter.

An overlay may select presentation, validation, construction, and resource policy. It may never replace or override
an Unknown/Unsupported mandatory structural fact, change a resolved structural fact, or grant Ada visibility. A
strict generator stops and requests a handwritten boundary outside derivation when required structure is unavailable.

Stable wire IDs, field/variant tags, compatibility, and evolution policy remain in the separate wire manifest and
are not serde annotations.

## Generator architecture

The pipeline has three versioned inputs: structural Type IR, the serde overlay, and generator configuration. It
validates them together, produces source-located diagnostics, and emits ordinary Ada packages that instantiate
generic combinators or contain direct traversals. Generated code depends only on `flyology_serde`; neither the
runtime value adapter nor a format backend links Libadalang or `flyology_type_ir`.

The shared extractor and IR can serve serde and wire generators because they stop before logical or wire lowering.
Generator utilities may later be shared as an offline library if both consumers need identical graph traversal and
diagnostic machinery. The runtime visitor, wire codec, schemas, and policy overlays remain independent.
