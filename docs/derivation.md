# Derivation

Routine public records, enums, arrays, and instantiated generic structures may receive generated adapters. Private,
limited, controlled, access-bearing, class-wide, task, and protected types require explicit policy or are rejected.

The offline generator will consume the versioned output of `flyology_type_ir`. It will not link Libadalang into the
serde runtime. Serde annotations provide reversible presentation policy such as rename, skip, default, optional,
text encoding, array-bound handling, and construction hooks. They do not provide Flyology wire identity.

The shared Type IR remains structural and lossless. Mapping an Ada declaration into serde logical events is a
serde-generator overlay, never an extractor decision. An imprecise scalar mapping or any unresolved mandatory
semantic fact is rejected with a source-located diagnostic requiring a handwritten adapter.

Generated deserializers must validate into component-local state and publish only after success. Discriminated
records are constructed once after their discriminants and active variant have been validated; a generator must not
change an existing object's discriminants in place.

Finite variant generation enumerates only exact, fixture-supported leaf paths from Type IR. It bounds the global
declaration set and every alternative membership independently, retains common declarations across leaves, and
keeps same-spelled branch declarations distinct. A dynamic, unresolved, or visibility-illegal discriminant path is a
checked adapter diagnostic, not permission to use representation values, summarized shapes, or guessed defaults.

Generated record lookup uses bounded name comparisons or package-private ordinals. Rename aliases are explicit,
ordered adapter metadata. The ordinals may change whenever code is regenerated and must not be serialized, placed
in Type IR, or treated as schema identity.
