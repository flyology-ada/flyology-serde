# Derivation

Routine public records, enums, arrays, and instantiated generic structures may receive generated adapters. Private,
limited, controlled, access-bearing, class-wide, task, and protected types require explicit policy or are rejected.

The offline generator consumes the reviewed versioned output of `flyology_type_ir`. It does not link Libadalang
into the serde runtime. The implemented fixture-gated v1 lowering accepts exactly one direct public definite record
with required visible Boolean, exact signed, and exact modular scalar components. Its closed canonical overlay owns
Ada binding names, logical presentation names, and serialization limits. Rename aliases, skip/default/optional
policy, text encoding, arrays, variants, private construction hooks, and other profiles remain checked future
extensions rather than implicit behavior. They do not provide Flyology wire identity.
Ada unit identities use language-defined case-insensitive comparison, while the overlay owns generated source
casing.

The shared Type IR remains structural and lossless. Mapping an Ada declaration into serde logical events is a
serde-generator overlay, never an extractor decision. An imprecise scalar mapping or any unresolved mandatory
semantic fact is rejected with a stable declaration or overlay path requiring a handwritten adapter. Future
extractor-backed diagnostics may additionally report a source location when the shared IR supplies one.

Generated deserializers must validate into component-local state and publish only after success. Discriminated
records are constructed once after their discriminants and active variant have been validated; a generator must not
change an existing object's discriminants in place.

Finite variant generation enumerates only exact, fixture-supported leaf paths from Type IR. It bounds the global
declaration set and every alternative membership independently, retains common declarations across leaves, and
keeps same-spelled branch declarations distinct. A dynamic, unresolved, or visibility-illegal discriminant path is a
checked adapter diagnostic, not permission to use representation values, summarized shapes, or guessed defaults.
Type IR v1 does not carry a mandatory predicate fact for record shapes, so production strict lowering stays closed
until the shared validator makes predicate-free admission provable. The reviewed fixture is accepted only by exact
source, semantic, and selected-unit identity.

Generated record lookup uses bounded name comparisons or package-private ordinals. Rename aliases are explicit,
ordered adapter metadata. The ordinals may change whenever code is regenerated and must not be serialized, placed
in Type IR, or treated as schema identity.

The generator materializes one-read, hash-attested Type IR schema/checker and fixture dependency bytes into an
isolated temporary root retained through the same-read checked document. `strict` is the default. Because reviewed Type IR v1 currently admits no
production document, successful generation is limited to the explicit `fixture_shape` test profile and produces a
machine-detectable fixture-only marker. It freezes the checked document, requires exact source, semantic, and
selected-unit digests, atomically claims a new output directory, writes an attested manifest last, and never
overwrites an existing directory. A verifier rejects every extra entry and runs as the fixture crate's Alire
pre-build action, so compilation follows verification of the same trusted-worktree path. This sequencing assumes
that no concurrent process mutates the path; it is not an immutable same-read handoff into GNAT.
Generated candidate state is private and limited; exact document completion precedes its only publication step.

The wire and serde projects now have concrete duplication in checker/schema digest attestation, isolated import,
same-read loading, and fixture gating. A future shared implementation should be a small Type-IR-owned offline loader.
Overlay parsing, lowering, Ada selected-name bindings, diagnostics tied to a consumer policy, and runtime traversal
remain separate.
