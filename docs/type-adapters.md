# Type adapters and construction modes

This document fixes the design direction for Ada type mappings. It does not make those mappings part of the shared
Type IR: they are serde adapter policy layered on a structural description of the Ada declaration.

## Ownership modes

Serialization borrows the source value for the duration of `Serialize`. Each `Put_Text` or `Put_Bytes` argument is
borrowed only for that call; a backend must consume or copy it before returning. A serializer that buffers output
owns its buffer but never retains a reference into the application value.

The bounded pull decoder copies text, bytes, and names into caller-provided buffers. Capacity failure is explicit
and does not silently truncate. An allocating facade may grow owned strings, vectors, maps, and candidate storage,
but it is a separate adapter over the same pull grammar. The explicitly named standard-heap text and byte adapters
document their eager scratch cost and cleanup. Application-specific allocating builders expose allocator and cleanup
behavior through generic actuals or constructor parameters.

A future zero-copy decoder is a separate capability. It may lend an input slice only to a callback or for one
documented pull step. The callback cannot return the slice, store it in a candidate, or use it after the next source
operation. Ada accessibility checks should enforce this where possible; otherwise the API does not offer borrowing.

## Scalars, strings, and bytes

The core numeric events cover exact 64-bit signed integers, exact 64-bit unsigned integers, and IEEE binary64. The
binary64 value is a safe semantic wrapper: finite values carry a valid Ada float, while positive infinity, negative
infinity, and NaN are explicit categories. It does not carry NaN payload or signaling identity. A generated adapter
range-checks before conversion. Wider integers, fixed point, decimal fixed point, and other floating formats require
an exact handwritten capability or are rejected. Format handling of all three nonfinite categories and signed zero
is a configured capability and can fail with `Unsupported_Value`; no adapter substitutes a rounded or textual
approximation implicitly.

`Text_Value` is a sequence of Unicode scalar values. The current `String` boundary carries validated UTF-8, not an
unspecified locale encoding. Generated adapters transcode predefined `String`, `Wide_String`, and
`Wide_Wide_String` according to an explicit policy and reject values that are not valid Unicode scalar sequences.
An application byte string maps to `Bytes_Value`, never text merely because its Ada representation is `String`.
Bounded text buffer lengths count UTF-8 bytes; source locations use the backend's separately reported offset unit.

Enumeration literals use their declared logical names after an explicit rename policy. Ada positions and physical
representation values are not serialized. Character types may map to one scalar text value or to their enumeration
literal, but the choice is adapter policy and must round-trip.

The reviewed generated-enumeration seam bounds total literals and every type, primary, and alias name. It validates
all declared mappings before a format event or typed read, then serializes the canonical primary name. Decode scans
every literal so an ambiguous handwritten matcher is rejected and an unmatched name is invalid. It never indexes by
`Enum_Rep`, assumes monotonic representation values, or emits an Ada position.

Adapters.Enumeration_Serializers is the additive serialization-only form for generated mappings that do not claim
construction authority. It accepts primary names only, copies them into bounded operation-local storage, and
reobserves every name before the first output event. The instance imports no deserialization policy or builder hook.

The bounded runtime supplies leaf adapters for Boolean, signed and modular integers, validated UTF-8 text,
caller-buffer bytes, the semantic binary64 wrapper, and application-defined null values. Byte decode has prefix and
exact-cardinality forms; the exact form leaves its candidate unchanged on a length mismatch. The binary64 adapter
checks the backend's nonfinite capability before serialization or candidate mutation and retains finite negative
zero. Null construction is an explicit callback into unpublished builder state.

## Optionals

Optionality is a logical `none` or `some(value)` construct, not merely a nullable field. This distinction preserves
nested optionals and `some(null)`. The event grammar uses an explicit optional container with zero or one child. A
JSON backend may choose a tagged representation when plain `null` would be ambiguous; a configuration
that requests the compact nullable representation must reject values it cannot distinguish.

For records, field absence is separate from an optional field whose value is `none`. Missing fields use the
field-specific required/default policy. A present optional field is decoded normally even when its value is none.

## Arrays and sequences

A one-dimensional Ada array maps to a sequence in component iteration order. For a constrained target, decoding
requires the input length to match. For an unconstrained target, policy chooses either a declared lower bound, a
canonical lower bound, or an explicit representation that carries bounds. The adapter never guesses a lower bound.

Multidimensional arrays map to nested sequences, one per index subtype, and must be rectangular. Each dimension has
an independent length and bound policy. Preserving noncanonical bounds requires explicit bound metadata in the
format-level representation; it is not inferred from the element sequence. Packed layout, component clauses, and
storage order do not affect the logical traversal.

Generic sequence and map combinators take a statically bound element or key/value adapter. Bounded instances carry
maximum length and construction capacity as generic actuals. Allocating instances own their containers and honor
the configured decode limits before growing them.

The general array combinator preserves whether the backend supplied a known length and independently enforces its
instance maximum and the operation's container-item limit. `Constrained_Arrays` stages a complete local candidate,
requires exact cardinality, and assigns only after `End_Sequence`; controlled or resource-owning elements use the
general builder seam. `Allocating_Sequences` supplies a standard-heap vector candidate for definite nonlimited,
copy-safe elements. It bounds and stages the full sequence before moving it into unpublished state; limited,
move-only, or identity-owning elements remain on the builder seam. The general map combinator bounds entry count and
checks the backend's map-key capability before the first event or builder callback. Its `Deserialize_Entry` callback
owns duplicate-key detection and replacement because logical key equality is adapter policy, not a format-parser
decision. `Allocating_Maps` supplies a standard-heap ordered map for definite, nonlimited, copy-safe keys and values.
Comparator equivalence defines its logical equality. `Decode_Policy.Maps.Duplicate_Keys` rejects, keeps the first
pair, or keeps the first key object while replacing its value. A rejected logical duplicate reports `Duplicate_Key`;
record and variant presentation-name duplicates remain `Duplicate_Field`.

Adapters.Fixed_Array_Serializers is the corresponding serialization-only constrained-array form. It emits the
array's complete range in Ada component order and imports no element-construction callback.

## Records, discriminants, and variants

Record fields are matched by bounded name lookup or generator-private local ordinals. Input order need not match
declaration order. The candidate tracks seen fields, aliases, duplicates, missing required fields, and defaults.
Aliases are accepted names for one field, not additional fields, and two aliases may not resolve ambiguously.

`Adapters.Records` is the bounded runtime combinator for a record with one or more logical fields. Its generic
instance supplies an ordinal enumeration, exact primary and alias names, bounded matcher, per-field serialization
and construction hooks, missing-field hook, and final candidate-validity hook. Metadata is stable and nonallocating
for an operation. Before its first backend event, the combinator bounds the number and length of names, validates
UTF-8, proves that every declared name maps only to its own ordinal, and rejects duplicate declared names. A
handwritten matcher may accept additional names, so decode still scans every ordinal and rejects runtime ambiguity
with `Application_Error` before duplicate policy or value consumption.

Serialization emits every ordinal in declaration order. Conditional omission is not implicit. Decode order is
`Begin_Record`, repeated name resolution and one child action, `End_Record`, missing hooks in declaration order, and
final candidate validation. Unknown-ignore and keep-first skip exactly one child. Keep-last passes
`Replacing = True`; its hook replaces only the unpublished candidate and must leave all owned resources safe for
outer rollback if decoding fails. Error paths retain the incoming spelling for unknown, ambiguous, duplicate, and
field-decode errors, and use the canonical primary name for missing fields, subject to `Error_Info`'s fixed
`Maximum_Name_Length`; longer names retain the bounded prefix and set `Name_Truncated`. A missing hook returning
`Applied = False` performs no field mutation. Null records use a separate adapter, since Ada has no empty enumeration
from which to manufacture a safe ordinal.

Adapters.Record_Serializers accepts only the source type, field ordinal, bounded primary-name metadata, and one
field serializer. It validates and reobserves all metadata before Begin_Record, emits every ordinal in order, and has
no aliases, missing/default policy, candidate, or decode operation. It is suitable for generated serialization-only
mappings; bidirectional mappings continue to use Adapters.Records.

A discriminated record is never built by changing the discriminants of an existing object. The adapter first
decodes discriminants and enough field state to select exactly one variant path, validates every component against
that path, then constructs the candidate once. In bounded mode, generated candidate storage has a declared capacity
for every supported alternative and rejects an oversized indefinite component. In allocating mode, candidate-owned
resources are released by rollback. Commit is the only publication step.

Defaulted discriminants and component defaults retain two separate facts: whether a default exists and, when it
does, whether its value is statically known. `no default` is not an unknown semantic fact. Variant choice semantics
come from the resolved Type IR condition tree, never reparsing presentation syntax in the serde generator.
Type IR also retains the resolved default-expression tree. The serde overlay chooses whether serialization or
construction policy uses that Known structure; it cannot alter the expression or replace a mandatory Unknown or
Unsupported default or bound. Array-bound transformation follows the same rule.

The reviewed finite-variant seam may lower exact nested variant paths to complete leaf alternatives only when the
mapping is finite, bounded, and lossless. A common declaration has one field identity across every leaf that contains
it; distinct branch declarations remain distinct even with equal presentation names. Constructor resolution happens
before the builder's `Begin_Alternative` hook. That hook stages only unpublished candidate state and must leave outer
rollback valid after a status or exception. After selected fields, defaults, and `End_Variant`, the final hook checks
or constructs the exact discriminant path. It cannot invent a discriminant choice or override structural facts.

Integer or dynamic discriminants, unresolved choices, unsafe constrained construction, and visibility gaps require a
generator diagnostic and a handwritten or generator-specific staged builder. A zero-field alternative still applies
unknown-field policy to supplied payload entries. An all-nullary sum uses a separate variant combinator so its logical
variant envelope is not silently changed to an enumeration.

## Private, limited, controlled, and concurrent types

Generated code respects Ada visibility. Seeing a full private view during extraction does not authorize a generated
adapter to name it. A private type needs public observers and constructors, an application-provided child adapter
with legal visibility, or a handwritten adapter. A companion schema can describe presentation policy but cannot
grant Ada visibility.

Limited values serialize through observers or legal component access. Deserialization uses an application-owned
transactional builder because assignment and default construction may be unavailable. For a limited published
object that cannot be atomically replaced, the application supplies a holder or transaction whose commit operation
provides the required publication semantics; serde does not pretend an in-place sequence of mutations is atomic.

Controlled candidates finalize exactly once. Commit transfers or consumes candidate ownership, while rollback
releases every acquired resource and is nonraising. Access, task, protected, class-wide, and interface values are
rejected by default. A handwritten adapter may snapshot application-defined logical state, but it never serializes
an address, task identity, protected-object state, dispatch tag, or controlled runtime metadata.

## Generic and indefinite types

Ada generic combinators are the normal reusable runtime mechanism: an optional, array, vector, or map adapter is
instantiated with statically bound child adapters and policy. There is no global runtime type registry and no
reflection lookup on the data path.

For adapters derived from an instantiated user generic, the future extraction path resolves supported type- and
value-affecting generic actuals into the shared Type IR. The current v1 identity model is fixture-gated for named
unconstrained type actuals and exact scalar or text value/object facts. Constrained type actuals and
expression-valued actuals are rejected. Positional, defaulted, boxed, package, subprogram, and nested cases are not
yet fixture-proven extraction support. Any unresolved formal on a mandatory path is a generation error. Indefinite
types use caller-provided bounds, a bounded candidate with explicit capacity, or an allocating builder; the core
never hides an allocation merely to make an indefinite result definite.

## Adapter production strategies

| Strategy | Best fit | Advantages | Required escape hatch |
| --- | --- | --- | --- |
| Ada-source derivation | Existing public Ada data types | Preserves Ada names and constraints; low duplication | Annotations and construction hooks for presentation, visibility, defaults, and unsupported semantics |
| Schema-first generation | External contracts and multi-language models | Contract is explicit before Ada layout; can generate value types and adapters together | Handwritten invariants, private APIs, controlled resources, and application-specific validation |
| Generic combinators | Standard containers and reusable application abstractions | Compile-time composition; no extractor or registry at runtime | A handwritten leaf adapter when the element or construction policy is not routine |
| Handwritten adapters | Private, limited, controlled, lossy-looking, or behavior-rich types | Full control of observation, validation, ownership, and commit | Review must test each implemented direction; deserializers require failure preservation and resource cleanup |

Source derivation and schema-first generation may both emit the same generic combinator instances. Handwritten
adapters implement the same runtime contracts. No strategy gets permission to weaken exactness, resource limits,
transactional publication, or error-path behavior.

## Automated extraction boundary

Libadalang is used only by the pinned offline extractor owned by `flyology_type_ir`. The planned extractor runs after
GNAT legality for the exact GPR project, scenario, target, and runtime. The current executable is deliberately
fail-closed and emits no IR. The checked v1 fixtures establish schema/model shape and GNAT legality coverage; they do
not yet prove implemented Libadalang extraction for every modeled construct. Once implemented, only fixture-gated,
precisely resolved named declarations, visibility-linked views, supported generic bindings, subtype relationships,
components, discriminants, representation-independent enumeration order, and exact discriminant/variant syntax
trees may enter strict consumer output.

Libadalang alone cannot choose serialized names, optional/default interpretation, unknown-field policy, array-bound
presentation, numeric loss policy, private construction hooks, resource limits, stable wire tags, or compatibility
rules. Serde obtains those decisions from a versioned annotation overlay or companion schema. Unknown or unsupported
mandatory semantic facts stop generation and request a handwritten adapter; the generator does not fill gaps with
heuristics.
