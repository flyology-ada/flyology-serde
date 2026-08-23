# Flyology Serde

`flyology_serde` defines format-agnostic serialization and deserialization contracts for Ada. Application
adapters traverse typed values through a common logical data model; JSON, CBOR, and future backends own the
concrete syntax.

The crate is experimental. The first milestone contains bounded interfaces, explicit nonraising errors, separate
serialization and construction adapters, and a counting serializer used to validate traversals. JSON, CBOR,
borrowing, allocating convenience adapters, and generated derivations remain follow-up work.

## Boundaries

- The runtime does not depend on Flyology tasking, remoting, Libadalang, or the shared Type IR tool.
- Ada memory layouts, stream attributes, access values, task state, and dispatch metadata are not serialized.
- Malformed input is reported through `Flyology_Serde.Errors`; it is not ordinary exception control flow.
- Allocation and borrowing are explicit adapter capabilities rather than hidden backend behavior.

See [architecture](docs/architecture.md), [type adapters](docs/type-adapters.md),
[Libadalang assessment](docs/libadalang-assessment.md), and [derivation](docs/derivation.md).

## Build and test

```sh
alr build
alr -C tests run
```
