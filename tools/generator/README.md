# Offline adapter generator

The supported generator is migrating to the nested Ada executable crate in `ada/`. The Ada candidate currently
builds and fails closed because the reviewed Type IR Ada checked-document API has not been published. Python remains
the authoritative fixture implementation until the reviewed cutover; see
[`docs/ada-generator.md`](../../docs/ada-generator.md).

The Ada crate also contains a deterministic in-memory payload renderer exercised only through a fixed constructor
under `ada/tests/src`. It compares the bytes after the legacy seven-line attestation header with fresh Python output
and the checked-in golden. It does not emit headers, manifests, directories, files, or CLI output, and is not a
production Type IR input path.

The offline Ada generator pins the corrected `mosteo/onox-json-ada` JSON 6.0.0 commit already used by Flyology and
the exact `sha2` 2.0.0 commit. Both dependencies remain confined to the generator crate. The runtime library and its
JSON and CBOR backends do not depend on either crate. Compiler resolution remains in the separate CI execution
attestation described by the architecture; the nested crate constrains supported GNAT releases to 13 through 16.

The Ada CLI has no resource defaults. Fixture mode requires `--limits` followed by sixteen positive
comma-separated values in `Generation_Limits` declaration order; callers select every externally effective bound.
Alire 2.1 records compiler-provider artifacts per host in its generated lock, so the nested lock is host-local and
ignored. JSON and SHA-256 remain exact Git commit pins in the manifest and dependency identity.

`generate.py` is the first fail-closed consumer of the reviewed Flyology Type IR v1 boundary. It is an offline
tool; generated packages depend on `flyology_serde`, but neither the serde runtime nor a format backend depends on
Type IR or Libadalang.

The initial lowering profile accepts exactly one direct, public, definite record whose components are visible,
required, nonaliased Boolean, exact signed integer, or exact modular integer types fitting the serde 64-bit scalar
events. Limited, controlled, access-bearing, tagged, class-wide, abstract, task, protected, discriminated, variant,
defaulted, indefinite, private-view, and unsupported scalar declarations fail generation. Scalar predicates fail
generation. Type IR v1 has no mandatory record-predicate fact, so strict production generation remains explicitly
closed until the shared boundary adds that fact or makes predicate-free records a validated extractor guarantee. An overlay
cannot change a Known structural fact, replace a mandatory Unknown or Unsupported fact, or grant Ada visibility.

Production `strict` is the default. Type IR commit
`78e6726a80d02b22f573fed3f65538cafd89fc0d` deliberately admits no production document yet, so the only successful
fixture currently requires both `--test-fixture-shape` and an overlay with `"fixture_only":true`. Generated fixture
Ada carries `FLYOLOGY_SERDE_TEST_FIXTURE_ONLY`; `check_release_markers.py` prevents it from appearing outside the
generator test tree.

```sh
python3 tools/generator/generate.py \
  --type-ir tools/generator/vendor/type_ir/fixtures/wire-record-shape.json \
  --overlay tools/generator/tests/fixtures/wire-record-overlay.json \
  --output /tmp/flyology-serde-generated \
  --test-fixture-shape
```

The overlay is canonical UTF-8 JSON with closed keys and is bound to both the Type IR source digest and semantic
fingerprint. It supplies only serde presentation, canonical Ada binding names, and serialization limits. The
`generate.py` reads `generator_impl.py` once, hashes it, and executes only those materialized bytes in an isolated
temporary import. The implementation reads and hashes the pinned checker, schema, fixture project, and selected unit once; materializes only
those attested bytes in a temporary root; disables bytecode output; and retains the root through `load_checked`.
The Type IR input is likewise copied from one read before checking. The checked document is frozen before lowering.
Fixture mode additionally requires the reviewed source, semantic, and selected-unit digests. Logical names are
nonempty printable ASCII within the runtime's 64-byte bounded lookup and an escaped-literal bound that keeps every
generated Ada line within 110 columns. Ada selected names obey Ada 2022 identifier,
reserved-word, and source-line bounds and must match the corresponding Type IR canonical declaration. The overlay's
`with_units` must exactly equal the required units in the attested project closure. The JSON Schema is a documentary
shape; the same-read canonical loader is authoritative for rules JSON Schema cannot express.
Ada unit identity is compared case-insensitively, as required by the language; the overlay owns the source casing
used in the generated declaration.

Publication builds a fresh staging directory, atomically claims a previously nonexistent output directory, links
regular output files into the claim, and publishes the manifest last. The manifest records input, semantic, overlay,
checker, schema, exact generator source, and output hashes. The tool never overwrites an existing directory.
`verify_manifest.py` rejects every unmanifested file, directory, symlink, or special entry and checks identities,
hashes, unit/file names, and fixture markers. The test crate runs it as an Alire pre-build action immediately before
compilation in a trusted, nonconcurrently-mutated worktree. It does not claim an immutable same-read handoff from
the verifier into GNAT. The generated deserializer owns a
private limited builder, reports whether it contains a published value, rejects an active re-entry, and publishes
its candidate only after exact root completion; rollback is nonraising.

The vendored checker/schema pair is temporary. The wire and serde consumers now duplicate the same digest
attestation, isolated import, same-read load, and fixture gate. That narrow loader belongs in a future Type-IR-owned
offline module. Overlay loading, lowering, Ada naming, emitted packages, and runtime traversal remain serde-owned.

Verify with:

```sh
alr -C tools/generator/ada build
alr -C tools/generator/ada exec -- gprbuild -p -P tests/scaffold_tests.gpr
sh tools/generator/ada/tests/smoke.sh
python3 -m unittest discover -s tools/generator/tests -p 'test_*.py'
python3 tools/generator/check_release_markers.py
python3 tools/generator/verify_manifest.py --require-fixture tools/generator/tests/golden
alr -C tools/generator/tests run
```
