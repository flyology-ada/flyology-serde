# Type adapters and construction modes

This document fixes the design direction for Ada type mappings. It does not make those mappings part of the shared
Type IR: they are serde adapter policy layered on a structural description of the Ada declaration.

## Ownership modes

Serialization borrows the source value for the duration of `Serialize`. Each `Put_Text` or `Put_Bytes` argument is
borrowed only for that call; a backend must consume or copy it before returning. A serializer that buffers output
owns its buffer but never retains a reference into the application value.

The bounded pull decoder copies text, bytes, and names into caller-provided buffers. Capacity failure is explicit
and does not silently truncate. An allocating facade may grow owned strings, vectors, maps, and candidate storage,
but it is a separate adapter over the same pull grammar. Its allocator and cleanup behavior are explicit generic
actuals or constructor parameters.

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

## Records, discriminants, and variants

Record fields are matched by bounded name lookup or generator-private local ordinals. Input order need not match
declaration order. The candidate tracks seen fields, aliases, duplicates, missing required fields, and defaults.
Aliases are accepted names for one field, not additional fields, and two aliases may not resolve ambiguously.

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
| Handwritten adapters | Private, limited, controlled, lossy-looking, or behavior-rich types | Full control of observation, validation, ownership, and commit | Review and tests must demonstrate round-trip and failure cleanup |

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
