# Ada build snapshot attestation proposal

Date: 2026-08-24

Status: proposal only; implementation and production action values are not authorized by this document.

## Problem and corrected boundary

The Ada generator needs a truthful `generator_identity_sha256` before it can add v2 headers and manifests. A
finished executable cannot obtain that identity by hashing the checkout from which it claims to have been built:
a stale executable could attest a clean newer checkout. Likewise, recomputing the expected Git-tree digest while
linking cached Alire objects does not prove that those source bytes entered the executable.

The attestation operation is therefore a dependency-free build-time stage, not a generator runtime preflight. It
copies every accepted generator source and pinned dependency blob into a fresh private snapshot while hashing those
same bytes. The final generator must be compiled only from that snapshot with fresh object and library directories.
A generator built from ambient source or cached dependency objects does not receive an embedded v2 identity and
remains ineligible for artifact publication.

The snapshot identity proves source and dependency content. Compiler, target, runtime, Alire version, Git
executable, generated stage-project/identity-body bytes, build switches, and build host belong to a separate
execution attestation. Neither identity grants Type IR extraction authority.

## Ownership and dependency direction

The temporary implementation is a private child of `Flyology_Serde_Generator`. It depends only on the Ada runtime,
the existing private `Build_Budgets`, `Build_Processes`, and handwritten `Build_SHA_256` units, plus narrow native
filesystem ABI leaves. It must not call the JSON or SHA-256 libraries that it is attesting. It introduces no runtime
dependency and no public or reusable Flyology attestation API.

The dependency-free bootstrap is a distinct `flyology_serde_generator_attest.gpr` and Ada main. That project has no
`with` of the ordinary generator configuration, JSON, or SHA2 projects and compiles only the parent package, budget,
process, SHA-256, attestation, and narrow native ABI closure. The supported workflow builds it immediately into
fresh object/executable directories using an exact caller-selected toolchain; no prior bootstrap object is reused.
Its complete source/project/native closure joins `provenance-files-v2.txt`, and its exact build/tool identity joins
execution attestation.

Type IR has confirmed that its future offline-support crate will own reusable resource, solution-lock, Git-tree,
retained-file, and snapshot mechanics. The Serde implementation is deliberately replaceable by that reviewed
surface. Serde continues to own only its provenance document, generated headers and manifest, overlay, lowering,
naming, rendering, publication, and build invocation.

## Proposed private API

`Flyology_Serde_Generator.Build_Attestations` owns two limited types bound to one nonreusing
`Build_Budgets.Session_Tag`:

- `Request` retains the absolute generator root, absolute Git executable, fresh staging parent, exact active Alire
  lock path, and one `(crate, active prefix)` claim per dependency;
- `Checked_Stage` owns a completely copied but unpublished snapshot, its generator source identity, the exact
  retained hashes of its execution inputs, and its fresh build-project path.

Every builder and query receives the same explicit session. `Seal` freezes a request. `Create_Checked_Stage`
constructs a candidate and replaces an earlier checked stage only after every read, hash, comparison, close, copy,
manifest check, and final closed-set rescan succeeds. Failure preserves the earlier stage and never publishes a
digest or build path from the candidate. Controlled finalization performs nonraising identity-safe cleanup; when
cleanup identity cannot be proven it retains the incomplete stage rather than deleting by a possibly replaced
name.

`Publish_For_Build` is the only ownership-transfer operation. It first makes the source/configuration portion of
the stage read-only, revalidates every retained identity and digest, writes a canonical ready manifest last, and
atomically renames the complete directory without replacement to a caller-selected path on the same retained
filesystem. The ready manifest records the generator identity, every staged logical path/digest/mode, and the
fresh output subdirectories that the build may mutate. Success detaches `Checked_Stage`; cleanup ownership transfers
to the build workflow. Failure preserves the unpublished owner. Missing, malformed, mismatched, extra, or stale
ready stages are never build inputs. A build failure removes only a stage whose retained parent/name/manifest
identity still matches; otherwise it leaves the stage for explicit inspection.

The caller supplies a complete `Attestation_Limits` record. It independently bounds path bytes, manifest bytes,
source files, source bytes per file and in aggregate, discovered entries, directory depth, aggregate discovered
path bytes, dependencies, dependency-tree entries, distinct blobs, tree-listing bytes, blob bytes per blob and in
aggregate, canonical-projection bytes, total staged bytes, diagnostics, Git commands, aggregate Git observation
time, and tool bytes per executable and in aggregate. It also contains one complete
`Build_Processes.Process_Limits` value. There are no defaults or production ceilings in the package. Test values
remain test-owned. Exact production values require a separate decision before any supported build action invokes
the API. The session's `Build_Budgets` work ledger is the sole aggregate work authority; the attestation limits do
not contain a second total-work field or counter.

Statuses distinguish invalid request/session, malformed provenance list, malformed canonical dependency identity,
malformed generator manifest, malformed active lock, closed-set mismatch, active-solution mismatch, dependency-tree
mismatch, source or staging I/O, Git rejection, process failure, cleanup failure, resource exhaustion, allocation
failure, and internal failure. The first failure remains primary and later mandatory cleanup damage is secondary.
Budget exhaustion remains primary over later cleanup damage. Unexpected state or cleanup damage poisons the
operation; ordinary content mismatch does not.

Before publication, the only successful observation is a fixed-size generator-identity copy. No candidate path,
allocating getter, raw access value, directory descriptor, Git result, dependency vector, mutable container, or
authority flag escapes. The caller supplies the final published path to `Publish_For_Build` and may use that path
only after successful ownership transfer. The caller and its collaborators must hold no writable alias to the
private stage; the package closes every writable descriptor before its read-only transition and revalidation. The
versioned execution-attestation document and its eventual public owner belong to the later build-handoff proposal;
this stage retains only the closed hashes needed to construct it and does not expose an ad hoc projection.

## Source snapshot transaction

The operation applies these steps in order:

1. Open the generator root and staging parent as retained directories, reject a final symlink or non-directory,
   establish distinct identities, and require the staging parent to be trusted, quiescent, and not writable by an
   adversary during the operation.
2. Read `provenance-files-v2.txt` once from a no-follow regular-file handle. Require one final LF, strict unsigned
   UTF-8 ordering, no blank or duplicate path, portable relative paths, the required self-entry, and every required
   top-level generator resource.
3. Independently derive the union of every exact required top-level resource and every permitted regular file in
   the allowed `src`, `native`, `schema`, and `templates` subtrees, without following symlinks. Compare that union
   exactly with the tracked list. Reject every unlisted relevant file, listed missing file, symlink, special node,
   disallowed suffix, or directory cycle. Suffix rules are root-specific: `src` permits `.ads` and `.adb`, `schema`
   permits `.json`, and `native` and `templates` use their complete explicitly allowed file sets.
4. Create one fresh exclusive private stage outside every input tree. For each listed file, retain one no-follow
   regular-file handle, read each byte once, charge it once as input, feed the same byte to handwritten SHA-256, and
   write that same byte to an exclusive stage file. Before closing, verify the source path still resolves to the
   retained file identity. A failed or ambiguous close prevents stage publication.
5. Parse the retained exact bytes of `dependency-identities-v2.json` with a closed handwritten parser. Require its
   canonical UTF-8 JSON encoding, exact keys, strict crate order, unique crates, lower-case digests and commits, and
   the tracked schema rules. Do not reopen it and do not consult the linked JSON library.
6. Parse the retained `alire.toml` and the one same-read active `alire.lock` with closed reviewed grammars. Require
   every manifest dependency and pin to match the dependency identity. The identity array must equal the complete
   set of linked non-toolchain solution entries, direct and transitive; an extra linked library fails closed.
   Require every such entry's commit, origin, path, optional subdirectory, and `lockfiled` fact to match exactly.
   The current Alire lock reports linked entries with `pinned = false`; that flag is not source-pin authority.
7. Repeat the independent source-tree discovery and root/path identity checks. A changed set or identity rejects the
   stage. This is a trusted-build-tree contract, not a claim to withstand an adversarial party that can replace and
   restore namespace entries between observations.

The tracked provenance contract must be revised before implementation to include every new bootstrap source and
project file. Tests and generated build output remain excluded.

## Dependency snapshot transaction

Each dependency prefix claim is matched by crate name to the closed identity and active solution. The prefix must
resolve to the expected linked root and subdirectory; a caller cannot redirect one crate to a different checkout.

The initial dependencies are Git identities. Registry support remains fail-closed until the Type IR offline-support
surface defines archive provenance. The Git executable must be a no-follow regular file below a trusted, quiescent
toolchain root. The attester opens and hashes its exact bytes once and retains its file identity. Before and after
every invocation, and again before stage publication, it reopens the executable no-follow, retains that new handle,
and hashes the bytes from that handle. Every observation must have the same identity and digest; the package does
not claim that a retained file handle governs the later pathname-based execution. Tool bytes have independent
per-tool and aggregate execution-input limits. Those limits count every returned byte across the initial read and
every revalidation read, not only the first observation. The retained Git execution tuple is exactly its
normalized absolute logical path, regular-file identity, lower-case SHA-256 of exact executable bytes, and the
validated `git --version` output; that tuple is an execution-attestation input, not generator source identity. The
later compiler and build-tool handoff applies the same no-follow identity/digest/revalidation rule.

For each Git identity the attester invokes that retained absolute executable through `Build_Processes`, with no
shell, an explicit canonical `--git-dir`, `--no-pager`, `--no-replace-objects`, and `--no-lazy-fetch`. Its closed
environment disables system/global configuration, pagers, optional locks, replacement objects, lazy promisor
fetching, and locale-dependent output. Only reviewed in-process Git built-ins are used; they must create no
descendants, change no process group/session/credentials, or write checkout state. A partial/promisor repository or
missing local object fails instead of fetching.

The sequence is:

1. Run bounded `cat-file -t` for the exact lower-case commit and require exactly `commit` plus LF, a zero normal
   exit, and empty stderr.
2. Capture `ls-tree -r -z --full-tree` with an explicit format containing mode, type, object identifier,
   `objectsize`, and raw path for that exact commit. Parse it as octets, independently sort by unsigned path bytes,
   and reject malformed records, duplicate or nonportable paths, non-blob objects, symlinks, submodules, modes other
   than `100644` and `100755`, excess entries, and excess bytes.
3. For each distinct object identifier, run bounded `cat-file blob`. Require a clean zero exit, empty stderr, exact
   listed decimal byte count, and no lazy-fetch/process-contract violation. Repeated object identifiers reuse the
   same retained exact bytes for every differently named or moded entry without recharging child capture.
4. Feed the exact blob bytes to handwritten SHA-256 and copy them to an exclusive stage path with the recorded
   mode. Stream the documented `flyology-git-tree-content-v1` canonical JSON projection through handwritten
   SHA-256 in strict path order.
5. Require the resulting content digest to match the tracked identity. Never copy cached objects, ALI files,
   libraries, build output, or mutable worktree files into the build stage.

The current trees independently reproduce their tracked values: JSON has 38 accepted blobs and digest
`ac367668690c734480b995e2d9f6279f1f3e24a8154aaeb752c03d55d6461162`; SHA2 has 18 accepted blobs and digest
`f52c14be55262ca2e1b3a0678ee4dc9390cdb535b73f3766bd7af749cf50cf7a`.

`dependency-identities-v2.json` currently lacks the effective source selection. A new closed tracked companion is
required before code: for the generator and each crate it records the Git-root subdirectory, source directories, and
any local configuration-pragmas file. Those cross-platform path facts join the generator source identity. The final
stage project does not import the original generator, JSON, SHA2, or generated Alire config GPRs and does not use
their cached libraries. It names only the reviewed source/configuration-pragmas paths inside the stage. Compiler
switches and host/build-profile selection are caller-supplied execution inputs, never inferred from ambient Alire
configuration, and join execution attestation. No cached dependency object or library is accepted.

## Exact charge ownership

`Build_Processes` remains the sole owner of argument/environment validation and materialization, process setup,
captured stdout/stderr input bytes, output-copy work, observation attempts, and cleanup. The attester never recharges
those events. It owns the following higher-layer charges, in this exact order; every amount is positive, atomic,
never refunded, and denial precedes the named effect:

| Event | Category and amount |
| --- | --- |
| Request text validation/materialization | `Work_Units`: one probe, then exact text bytes |
| Directory entry/type observation | `Work_Units`: one probe, then exact relative-path bytes |
| Local source/manifest/lock/tool read attempt | `Work_Units`: one before the attempt |
| Positive local read | `Input_Bytes`: exact returned bytes before retention |
| Parse or lexical scan | `Work_Units`: one per examined byte |
| Path/key comparison | `Work_Units`: one probe, then `min(left length, right length) + 1` |
| SHA-256 input from retained local or Git bytes | `Work_Units`: exact bytes before `Update` |
| Stage write | `Work_Units`: one attempt, then exact bytes before the write |
| Git stdout parse after runner copy | `Work_Units`: one per examined byte |
| Canonical projection emission | `Work_Units`: exact emitted bytes before `Update` |
| Stage rehash/readback | `Work_Units`: one per read attempt, then exact compared bytes |
| Exclusive directory or file creation | `Work_Units`: one before each creation attempt |
| Generated project, identity body, or ready-manifest emission | `Work_Units`: exact nonempty emitted bytes before write |
| File-mode application or read-only transition | `Work_Units`: one before each mode-change attempt |
| Atomic no-replace stage publication | `Work_Units`: one before the rename attempt |

Internally generated stage bytes never spend `Input_Bytes`. Source/manifest/lock bytes spend input only at their
same-handle read; Git bytes spend input only in the runner capture. Every initial or revalidation tool read charges
its exact returned bytes once to `Input_Bytes` before retention and charges the same bytes once to `Work_Units`
before hashing. A repeated blob object is captured, hashed, and retained once, then each stage write spends only its
own write work. Physical caps are checked before allocation, but an already returned local, tool, or child byte is
still attempted against input before a per-file/per-tool/per-blob cap so the one-extra boundary is observable.
Cleanup is uncharged. A prelatched status, foreign session, or invalid retained owner is a zero-charge no-op. A
zero-byte hash, generated-text, or stage-write subcharge is omitted; its read, creation, or write-attempt probe
remains charged where applicable. Exact API-level probes and denial points must be transcribed into a versioned
cost table before body implementation and asserted as complete charge traces.

## Generator identity and build handoff

After all source and dependency entries validate, the package streams the exact
`flyology-serde-generator-provenance-v2` canonical JSON projection through handwritten SHA-256. It writes a private
generated Ada body containing that digest and a build project that refers only to stage-internal source/config
projects and fresh stage-internal object, library, and executable directories. The value is private generator build
configuration, not a public serde API constant.

The digest formula is exactly ASCII `flyology-serde-generator-provenance-v2`, LF, the canonical JSON object, and
one final LF. The retained canonical dependency array is embedded without its file-ending LF. `files` contains only
the tracked generator logical paths and exact source-file digests; the generated stage project, enabled identity
body, ready manifest, and execution-attestation files are deliberately excluded to avoid circularity. Their exact
deterministic bytes and digests join execution attestation and are reverified before and after compilation.

The tracked source contains a private build-identity specification and a disabled development body. A direct or
ordinary Alire build can therefore report only that no attested identity is present and remains structurally unable
to publish generated adapters. The snapshot stage supplies the only enabled body, and the main executable must query
it on every publication path so the linker cannot discard or bypass it. The normal project alone includes the
tracked disabled-body source directory. The stage project explicitly excludes that directory and includes only the
separate generated enabled-body directory, preventing duplicate or ambiguous body selection.

`Checked_Stage` does not itself claim that a compiler consumed the snapshot. A separate build handoff must replace
the attester process with an exact caller-selected `gprbuild`/compiler transaction or otherwise supervise a build
tool that can create descendants. `Build_Processes` cannot run `gprbuild` because its reviewed contract permits
only one child that creates no descendants. The handoff constructs a noninherited environment: project/source/link
search variables are absent, toolchain paths are exact, every permitted GPR external is explicit, and ambient
`ADAFLAGS` or equivalent injection is rejected. One generated project has no imported GPR and uses only absolute
stage-internal source and configuration-pragmas paths plus fresh candidate output directories. The build uses no
ambient Ada objects or libraries and verifies the compiler's loaded source/object/project closure remains beneath
the retained stage or exact toolchain root.

After compilation, the handoff revalidates the ready stage, runs the hidden candidate in its identity-report mode,
and requires the exact embedded generator identity before accepting it. It then publishes the executable through
an identity-checked atomic replacement that preserves any prior successfully attested executable until success.
Stale candidates and failed builds are removed only through retained identity-safe cleanup. The final execution
attestation records the exact stage manifest, tool identities, switches, environment, and candidate digest before
binary publication. The normal generator executable cannot mint or override its embedded identity.

Until this handoff and its production action limits are reviewed, `alr build` may continue producing the
development/fail-closed generator but no resulting binary may claim a v2 identity or publish generated artifacts.

## Required verification

Tests must cover exact and one-less boundaries for every limit; arbitrary Ada bounds; source list LF/CR, ordering,
duplicate, missing, extra, path, suffix, symlink, special-file, and mutation cases; canonical dependency JSON and
active-lock duplicate/unknown/table variants; wrong prefix, subdirectory, commit, origin, source selection, build
recipe, object type, mode, blob size, and content; replacement-object and lazy-fetch rejection; Git nonzero exit,
signal, timeout, stdout/stderr limit, and malformed NUL output; source/stage close failures; pending abort at every
ownership transfer; prior-stage preservation; deterministic charge traces and canonical bytes; independent
Python-oracle digest parity; clean compilation using only stage paths; and macOS/Linux CI.

The matrix also includes empty blobs; a repeated object identifier at different paths and modes; malformed decimal
`objectsize`; Git-executable replacement; ambient GPR/Ada project shadowing; exact generated identity/project bytes;
binary NUL and high-byte blob content; a retained writable alias across attempted publication; Git replacement
between blob commands; zero-byte charge traces; and a fresh bootstrap build with no external library or prior object
closure. Aggregate completed-Git elapsed time is measured monotonically around each complete `Run` call, accumulated
with checked arithmetic, and checked before the next command and before stage acceptance. Process count and
per-command timeout bound ordinary Git observation, but the proposal does not claim a hard call-latency or wall-time
bound: `posix_spawn` and mandatory cleanup can exceed the runner timeout.

Every architecture, implementation, and fix diff receives the repository's P0/P1/P2 cycle. P0/P1 are fixed before
commit; P2 is fixed by default.

## Review disposition

Two independent architecture reviewers examined the proposal and every corrective diff. The first pass rejected
runtime self-attestation because a stale executable could hash a newer checkout and cached objects would not be
bound to the observed source bytes. Later passes corrected stage-path lifetime, writable-alias, tool replacement,
identity-body selection, aggregate-work authority, tool reread charging, and exact zero-byte/event charging. The
final narrow reviews report P0 none, P1 none, and P2 none. This disposition authorizes committing the proposal; it
does not authorize implementation bodies, production limits, a build action, or generator publication.
