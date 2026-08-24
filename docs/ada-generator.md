# Ada generator

The supported derivation pipeline is moving to a separate offline Ada executable crate,
`flyology_serde_generator`. The crate lives below `tools/generator/ada`; it is not an Ada child of
`Flyology_Serde`, and the `flyology_serde` runtime does not depend on it, `flyology_type_ir`, or Libadalang.

## Implementation status

At serde commit `92d9b59`, only the Python fixture-gated generator is implemented. Type IR commit `460e125` does
not yet provide the concrete Ada codec, checked owner, immutable index, or extractor authority required below. The
authority modes and Ada publication pipeline in this document are contracts for the migration, not claims about
the current executable. Consumer-owned scaffolding may be built before that dependency is available, but it must
remain fail-closed and must not duplicate the Type IR loader. Python remains authoritative for the current fixture
path; it becomes only a differential oracle after the reviewed Ada cutover. Production record lowering also stays
closed until Type IR supplies the mandatory record-predicate guarantee described in [Derivation](derivation.md).

## Authority modes

The generator has two deliberately different input modes.

Future production source mode calls the reviewed `flyology_type_ir_extractor` Ada library. The extractor owns GNAT
legality, the exact project/scenario/target/runtime/tool closure, Libadalang, and its consistency snapshots. It
returns a separate private limited production-checked type with no public constructor or conversion from a
persisted owner. Only successful extractor construction makes it query-eligible; its default and every failed
result are empty. The generator retains a successful owner for the complete query and lowering transaction. No
persisted JSON document, context field, command-line profile, Boolean, or caller-supplied trust value can create
production authority.

Future persisted-document mode loads canonical Type IR through the root Type IR Ada library. It can produce only a
structural or consumer-shape checked owner. This mode is for fixtures, audit, and conformance. Fixture generation
requires an explicit command-line option, an exact locked source and semantic identity, and a fixture-only overlay.
Its output carries a release-rejected marker. It is never a production fallback.
The Ada manifest verifier requires the v2 fixture flag and both generated Ada files require the literal
`FLYOLOGY_SERDE_TEST_FIXTURE_ONLY` header. The fixture build checks both immediately before compilation, and release
CI scans the repository and every produced artifact for the fixture marker or flag outside the closed generator
test tree. Nonfixture output requires and verifies `FLYOLOGY_SERDE_GENERATED`; that marker is not release-rejected.

Both checked owners are limited and remain alive through lowering. Serde queries them through the immutable
cursor or callback API; it does not copy a mutable Type IR graph or retain an access value after its owner or query
scope ends. Every failed load or extraction leaves its result empty and query-ineligible, releases owned resources,
and preserves the primary bounded diagnostic.

## Ownership boundary

Type IR owns structural model construction, canonical Type IR JSON, same-read checked loading, semantic
validation, source and semantic fingerprints, stable-ID indexes, extraction authority, and checkout/resource
attestation. Its extractor alone depends on Libadalang.

The serde generator owns its closed overlay model and parser, logical lowering, exact scalar capability checks,
Ada naming, rendering, generated builders, artifact names, diagnostics for serde policy, the generation manifest,
and publication. An overlay may consume a Known structural fact. It may not change that fact, replace a mandatory
Unknown or Unsupported fact, grant representation visibility, or infer encoding from a representation clause.

Generated packages depend on `flyology_serde` and the user Ada units named by their bindings. Their infrastructure
dependencies exclude the generator, Type IR, and Libadalang. JSON and CBOR backends, runtime traversal, builders,
budgets, capabilities, and error paths remain unchanged and are not shared with Flyology wire codecs.

## Output transaction

The output path must not exist. Before generation, the tool resolves it away from every input, the Type IR
checkout, the generator checkout, and any staging path. It rejects a symlink or special entry at every trusted
filesystem boundary.

The tool reads each consumer-owned byte input once, retains or copies exactly those bytes, and performs parsing,
hashing, and lowering from the retained bytes or checked owner. Extractor-owned production source consistency is
instead established by the extractor's project snapshots. The generator renders every artifact, checks UTF-8, LF
endings, file names,
110-column Ada source, hashes, and the closed manifest before publication. It then claims a fresh empty output
directory, publishes regular artifacts without replacement, and publishes the manifest last as the completion
marker. After failure the completion manifest is never published, cleanup is nonraising and best-effort, and an
incomplete generator-owned directory may remain if cleanup itself fails. Such a directory fails verification and
must never be compiled. The tool never modifies a pre-existing path. A consumer accepts only a complete directory
whose manifest verifies every entry. Publication assumes the trusted local tree is not concurrently mutated; it is
not an immutable handoff into GNAT.

## Determinism and provenance

The Ada generator preserves the existing generated adapter semantics and the JSON/CBOR fixture bytes. It cannot
truthfully preserve the legacy Python provenance bytes: the existing headers and manifest identify
`generator_impl.py`. The Ada pipeline therefore uses manifest/header version 2.

The generator source identity is SHA-256 over the ASCII domain bytes
`flyology-serde-generator-provenance-v2` followed by LF and one canonical UTF-8 JSON document. The document has
exactly `provenance_version`, `dependencies`, and `files`; `provenance_version` is 2. Each file entry has exactly
`logical_path` and `sha256`.

The tracked `provenance-files-v2.txt` is the closed file enumeration: one normalized logical path per LF-terminated
line, strictly sorted by unsigned UTF-8 bytes, with no blank or duplicate line. It must name itself,
`dependency-identities-v2.json`, `flyology_serde_generator.gpr`, `alire.toml`, every recursively discovered regular
`.json` file below `schema`, every recursively discovered regular `.ads` and `.adb` file below `src`, every regular
source file below `native`, and every recursively discovered regular file below `templates`; no other path is
allowed. The platform-specific generated `alire/alire.lock` is host-local and ignored. Logical paths are relative to
the crate root, use `/`, contain only portable ASCII letters, digits,
`_`, `-`, `.`, and `/`, and contain no empty, `.` or `..` component. Every entry must be a regular non-symlink file
and its digest is over exact bytes.

The dependency array is exactly the canonical contents of tracked `dependency-identities-v2.json`, sorted by ASCII
crate name. It includes every linked non-toolchain library dependency and excludes GNAT/compiler toolchain packages,
which belong only in the CI execution attestation. Every entry has `crate`, `version`, `source_kind`, `origin`, and
`content_sha256`; a Git entry also has
`commit`. `origin` is an already canonical printable-ASCII URI stored and hashed exactly as written; the generator
performs no URL equivalence normalization. A release identity permits only `git` or `registry` source kinds and
rejects a local path. The generator verifies these identities against `alire.toml` and the active Alire solution;
the generated, platform-specific `alire.lock` is host-local and is not part of the cross-platform generator identity.
The linked JSON and SHA-256 dependencies remain exact Git commit pins in `alire.toml` and the dependency identity.
CI selects a supported compiler before the nested build resolves its host-local toolchain provider.

For a registry dependency, `content_sha256` is the SHA-256 recorded by the locked registry origin over the exact
downloaded archive bytes. For a Git dependency, it is SHA-256 over the ASCII domain
`flyology-git-tree-content-v1` plus LF and canonical JSON for the exact commit tree. That JSON is an array sorted by
unsigned UTF-8 path bytes. Each entry has exactly `mode`, `path`, and `sha256`; `mode` is `100644` or `100755`, path
uses the logical-path rules above, and the digest is over exact blob bytes. Symlinks, submodules, duplicate paths,
and other modes are rejected. The verifier obtains entries from the exact locked commit without checkout filters
and recomputes this digest. The closed dependency file shape is normative in
`tools/generator/ada/schema/dependency-identities-v2.schema.json`.

Canonical JSON uses lexicographically sorted object keys, array order just specified, decimal integers, no optional
whitespace, and one final LF. The identity excludes generated artifacts, compiler output, executable bytes,
timestamps, permissions, absolute paths, host, locale, environment, and process state, so it attests source and
locked dependencies rather than which executable ran. Compiler, target, runtime, scenario, build switches, and the
exact host Alire lock belong in a separate CI execution attestation outside the closed generated directory. They do
not affect rendered Ada or the cross-platform golden manifest.

The offline executable pins the corrected `mosteo/onox-json-ada` JSON 6.0.0 commit already established in Flyology
and the exact `sha2` 2.0.0 commit. Their full Git-tree content identities are recorded in
`dependency-identities-v2.json`. They remain generator-only dependencies; toolchain selection remains in the CI
execution attestation. Adding the reviewed Type IR library later adds another exact non-toolchain source identity.

The first seven lines of each v2 Ada artifact are a closed attestation block: the fixture marker or a nonfixture
generated marker, generator version, generator source identity, Type IR document/extraction identity, Type IR
semantic fingerprint, overlay SHA-256, and a terminating blank line. Migration comparison removes exactly this
seven-line block from both `.ads` and `.adb` and compares all remaining bytes. The complete manifest shape and
literal header grammar are normative in
`tools/generator/ada/schema/serde-generation-v2.schema.json`. The manifest is encoded with the same canonical JSON
rules as the identity document. It replaces v1's Python checker and single-source fields with the generator identity
and locked Type IR library identity; the migration test permits only the schema's named field transformation and
the artifact hashes caused by the closed header replacement. Once v2 goldens are accepted, complete
specifications, bodies, and manifests compare byte-for-byte again.
The Ada verifier, not ordinary JSON Schema validation, enforces every `x-flyology-*` rule, including canonical
encoding, strict unique path ordering, the literal seven-line header, header-to-manifest equality, and the fixture
flag/authority/marker relationship.
`type_ir_library.content_sha256` must exactly equal the content digest for `flyology_type_ir` in
`dependency-identities-v2.json`; it is never an executable or arbitrary checkout digest. Negative tests cover
unsorted and duplicate logical paths, header/manifest mismatches, extra directory entries, and each invalid
fixture/authority/marker combination.
`type_ir_document.context_sha256` is present only for production authority and hashes the canonical Type IR
extraction-context projection defined by the pinned Type IR API. Consumer-shape fixture output omits it. Structural
documents can be checked for audit, but v2 never publishes adapter artifacts from structural authority.

Before cutover, Python remains authoritative for the fixture path and Ada is the candidate. Both implementations
generate into fresh directories. One shared header parser removes exactly the seven-line attestation block from
each specification and body and compares every remaining byte; tests separately validate the complete v2 artifacts
and compare runtime behavior exactly. After cutover, Ada is authoritative and Python is only a differential oracle.
Python leaves supported and installed paths after the Ada loader, verifier, negative cases, generated-package
compilation, and macOS/Linux fixture runs are authoritative.

The first Ada rendering milestone is deliberately narrower than generation. A serde-private, immutable lowered
record owner can be constructed only by trusted child units. The current fixture child is compiled from the nested
test source directory and absent from the executable project. It consumes the real checked Ada overlay owner but
accepts only the exact reviewed Type IR v1 fixture commit, source and semantic identities, record and component
stable IDs, field order, with-unit, and canonical Ada record, component, and type bindings. This is a fixture oracle,
not Type IR authority. The output unit must equal the Type IR accessibility context's consumer unit because changing
it could reuse visibility facts in another Ada context. Logical and presentation names and runtime limits remain
overlay policy.

Lowering shares the operation budget used by overlay loading. Scalar, count, length, and copy observations use the
checked overlay query charges. After validating all fixed structural claims, lowering charges one separate work unit
for the record and each of its three fields. Queried text first passes an intrinsic 128-byte destination-capacity
check and then copies into fixed scratch storage. The limited result stays default-empty through every observation,
validation, and charge and is populated only after complete success, with `Valid` set last. A mismatch reports the
unsupported-model status without poisoning the budget. Budget denial and `Storage_Error` poison it; unexpected
exceptions also poison it and preserve an earlier diagnostic. A prelatched diagnostic is a no-op.

The deterministic renderer accepts that owner and produces exactly two unpublished in-memory Ada payloads beginning
at the first `with` clause. It emits no attestation header, manifest, directory, or file. Tests remove exactly the
legacy seven-line fixture header and compare every remaining byte with both a fresh Python generation and the
checked-in golden. Exact and one-less lowering work limits, prelatched failure, structural mismatch, and policy
propagation are tested directly. The production entry point does not compile the fixture child, does not call the
renderer, and continues to return `generator/type-ir-ada-api-unavailable` without publishing output.

Rendering owns two artifact-file charges, each artifact's complete payload bytes, aggregate rendered bytes, and
one work unit per output byte. The renderer separately charges one work unit per observed with-unit and field. It
validates the complete model, reserves both file slots, then charges each deterministic output chunk against the
current file, aggregate output, and work limits before scanning or appending it to a private candidate. The
candidate replaces an earlier result only through a nonallocating owner-pointer swap. Denial poisons the operation
budget, retains all earlier charges, and leaves an earlier rendered result unchanged. The payload grammar uses
explicit LF bytes, printable ASCII, a required final LF, derived portable filenames, and the repository's 110-column
ceiling. Payload observation is length plus caller-buffer copy; it does not allocate another complete result. These
test payloads are not Type IR authority and do not make Python an oracle yet; Python stays
authoritative until the complete checked-owner, attestation-header, verifier, manifest, publication, and platform
cutover gates close.

The private `Build_Processes` foundation is implemented for the forthcoming dependency-attestation layer. It owns
bounded explicit argv/environment construction, serialized CLOEXEC-safe spawn setup, alternating stdout/stderr
capture, process-group cleanup, exact-leader reaping, session-bound results, and the caller-supplied build budget.
It is not called by the executable yet and selects no public action limit. Its exact charge, timeout, and fail-stop
contract is recorded in the [Ada build process runner review](reviews/2026-08-24-ada-build-process-runner.md).

## Resource limits and errors

Offline operation is allocating but bounded. Each operation receives one immutable `Generation_Limits` value and
creates one mutable, noncopyable operation budget shared by every consumer-owned stage. The limits have independent
positive maxima for bytes per consumer-owned input, aggregate consumer input bytes, decoded string
bytes per string, number-token bytes per token, JSON nesting, members per object, elements per array, Type IR JSON
nodes, overlay JSON nodes, rendered bytes per file, aggregate rendered bytes, artifact files, aggregate diagnostics,
diagnostic UTF-8 bytes, and work units. Counters use a wider checked type; overflow is a limit failure, and a value
at the maximum is accepted while maximum plus one is rejected before allocation or publication.

The Type IR loader owns and charges retained Type IR source octets and its decoded nodes. The serde overlay loader
separately owns and charges retained overlay source octets and its decoded nodes. Each JSON codec charges a decoded
string by UTF-8 octets after escape processing, a number by source-token octets, nesting on successful container
entry, members or elements when accepted into that parent, and one node in its own per-codec counter when a value is
accepted. The renderer owns output bytes and files. The orchestration layer owns aggregate input, output,
diagnostics, and work. Work is charged for each input octet processed by lexical validation, the JSON parser,
canonical re-encoding, canonical comparison, and hashing; each duplicate-key or semantic-uniqueness comparison;
each accepted JSON node; each lowered declaration or component; and each rendered output octet. A layer never
charges work owned by another layer. A denied charge permanently poisons the operation budget; it cannot be reset
or reused by a later stage.

The overlay path loader opens the final path without following a symlink, requires the retained descriptor to name
a regular file, reads and accounts the exact bytes from that descriptor, and requires successful close before the
document can be published. A FIFO, device, directory, or final symlink is rejected before parsing. The small C ABI
leaf exists only to expose an open using header-defined `O_NOFOLLOW`, `O_CLOEXEC`, and `O_NONBLOCK` flags and an
`fstat`/`S_ISREG` query. Ada decides whether the retained descriptor is acceptable and owns reading, bounds, status
classification, close verification, and cleanup.

Checked request and overlay owners expose no allocating `String` getters to production lowering. Request paths use
length and caller-buffer copy queries; they remain opaque non-NUL pathname octets and are not reinterpreted as
Unicode. Checked overlay v1 text is printable ASCII, so its reported length is both Ada `String` elements and UTF-8
octets. Scalar, count, and length queries charge one work unit before publishing a result. A text copy charges one
probe unit, then exactly the text length before copying when the caller buffer is large enough. An undersized buffer
changes only its copied flag, while a denied charge poisons the budget, preserves every result actual, and reports
resource exhaustion. A latched diagnostic permits only nonallocating selection of an immutable retained component;
it causes no budget, diagnostic, or result mutation. Indexed range checks are uncharged programming checks after
diagnostic and poison precedence; they never classify external input.

Checks occur in this order: aggregate and per-input raw byte bounds during read; token/string/nesting and local
container bounds during parse; the applicable per-codec node and aggregate work bounds on acceptance; semantic
validation and lowering;
then file and output bounds during render. The first failure remains primary. A bounded-input or semantic failure
returns its stable diagnostic, discards its unpublished candidate, and leaves any previously checked owner
unchanged. Resource exhaustion reports a distinct
resource status. `Storage_Error` or an unexpected internal exception is caught at the executable boundary, retains
the primary status when one already exists, performs nonraising best-effort cleanup, never publishes a completion
manifest, and returns an internal-failure status otherwise.
