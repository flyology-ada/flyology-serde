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
text, byte, copy-safe vector, and ordered-map candidates. Application builders still own allocating records,
custom collections, and limited or move-only sequences and maps. The first offline
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

`flyology_json=0.1.0-dev` resolves from the Flyology Alire index without a Git
or path pin. Because the development entry can advance, the maintained lock
checker rejects any source other than the reviewed commit before a change can
pass CI. It also attests the exact Flyology JSON release-metadata block
(`a11cf63220d0244a65efd72d94c25adb09ba9443e5494d51d8487890abca2a3f`)
and rejects unexpected solution states. Configure the Flyology index ahead of
the community index once:

```sh
alr index --reset-community
alr index --add=git+https://github.com/flyology-ada/alire-index.git \
  --name=flyology --before=community
```

```sh
alr update
alr -C tests update
python3 tools/check_flyology_json_dependency.py alire/alire.lock
python3 tools/check_flyology_json_dependency.py tests/alire/alire.lock
python3 -m unittest discover -s tools -p 'test_check_*.py'
alr build
alr -C tests run
scripts/check-test-hook-elision.sh
alr -C tools/generator/ada build
alr -C tools/generator/ada exec -- gprbuild -p -P tests/scaffold_tests.gpr
sh tools/generator/ada/tests/smoke.sh
python3 -m unittest discover -s tools/generator/tests -p 'test_*.py'
python3 tools/generator/check_release_markers.py
python3 tools/generator/verify_manifest.py --require-fixture tools/generator/tests/golden
alr -C tools/generator/tests run
```
