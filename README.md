# Flyology Serde

`flyology_serde` defines format-agnostic serialization and deserialization contracts for Ada. Application
adapters traverse typed values through a common logical data model; JSON, CBOR, and future backends own the
concrete syntax.

The crate is experimental. It contains bounded interfaces, explicit nonraising errors, transactional
construction, decode budgets, exact integer and UTF-8 adapters, optional and array combinators, and a counting
serializer used to validate traversals. The bounded enumeration combinator adds representation-independent logical
names and aliases. The bounded record combinator adds exact name/alias metadata, duplicate and unknown-field
policy, missing-field hooks, and final candidate validation. Bounded finite and nullary variant combinators preserve
alternative identity, selected field membership, transactional construction, and the logical variant envelope.
JSON and CBOR provide bounded readers and writers, allocating writers, copied-input root facades, and standard-heap
text and byte candidates. Application builders still own allocating records, maps, and arrays. The first offline
Type IR consumer generates one fixture-gated direct public record profile; production strict generation remains
closed until the separately reviewed Type IR extractor publishes an admissible document.

## Boundaries

- The runtime does not depend on Flyology tasking, remoting, Libadalang, or the shared Type IR tool.
- Ada memory layouts, stream attributes, access values, task state, and dispatch metadata are not serialized.
- Malformed input is reported through `Flyology_Serde.Errors`; it is not ordinary exception control flow.
- Allocation and borrowing are explicit adapter capabilities rather than hidden backend behavior.

See [architecture](docs/architecture.md), [type adapters](docs/type-adapters.md),
[JSON backend](docs/json.md), [CBOR backend](docs/cbor.md), [allocating modes](docs/allocating.md),
[Libadalang assessment](docs/libadalang-assessment.md), and [derivation](docs/derivation.md).
The initial generator and its deliberately narrow support matrix are documented in
[tools/generator/README.md](tools/generator/README.md).

## Agent setup

This repository provisions shared Ada agent rules and its serde-specific instructions through
[APM](https://microsoft.github.io/apm/). Install and verify the validated APM release, reproduce the locked
dependency graph, and generate the committed Codex instructions with:

```sh
curl -sSL https://aka.ms/apm-unix | sh -s -- @v0.28.0
apm --version

apm install --frozen
apm compile --target codex
apm audit --ci --no-policy
```

`apm.lock.yaml` pins the shared `flyology-ada/agents` revision. Change the local instruction primitive under
`agent-packages/repository/`, not generated `AGENTS.md`, and commit the primitive, lockfile, and regenerated
output together. This repository has no separate organization-policy package, so its audit explicitly verifies
the lockfile, deployed content, and drift without policy discovery. Start a fresh client session after provisioning
so it discovers the generated skills.

## Build and test

```sh
alr build
alr -C tests run
python3 -m unittest discover -s tools/generator/tests -p 'test_*.py'
python3 tools/generator/check_release_markers.py
python3 tools/generator/verify_manifest.py --require-fixture tools/generator/tests/golden
alr -C tools/generator/tests run
```
