# Ada generator architecture review — 2026-08-23

Scope: migrate the supported offline serde derivation pipeline from Python to Ada while preserving the runtime and
the shared Type IR boundary.

## Decision

- Add a nested executable crate named `flyology_serde_generator` with Ada root
  `Flyology_Serde_Generator`. It is not a child unit of `Flyology_Serde`.
- Keep the root runtime crate independent of the generator, Type IR, Libadalang, process execution, and any new
  JSON dependency.
- Use an extractor-owned limited production document only in same-process source mode. Persisted Type IR remains a
  structural, fixture, or audit input and cannot authenticate its own extraction transaction.
- Keep Type IR loading, immutable indexes, structural diagnostics, extraction authority, and resource attestation
  in Type IR. Keep serde overlays, lowering, naming, rendering, manifests, builders, and publication in serde.
- Require a fresh nonoverlapping output directory, validate all artifacts before publication, publish the manifest
  last, and clean only generator-owned incomplete state after failure.
- Preserve runtime JSON/CBOR bytes and generated adapter semantics. Introduce provenance version 2 rather than
  retaining a false Python implementation digest.

## First independent cycle

Three read-only reviewers inspected the published serde baseline and the Type IR consumer boundary.

- P0: one external implementation blocker. Type IR commit `460e125` has no concrete Ada canonical decoder,
  same-read checked owner, immutable index, fingerprint implementation, or production extraction authority. The
  serde generator must not pin that commit or duplicate its Python loader.
- P1: persisted JSON must never become production authority; an extraction failure must leave its limited result
  empty and safe to finalize; the generator must remain a nested offline crate; exact legacy provenance bytes are
  incompatible with honest migration; and publication must preserve the complete same-read, no-overwrite,
  manifest-last integrity contract.
- P2: port negative coverage for duplicate and noncanonical JSON, huge integers, changed inputs, special entries,
  rollback and reuse, marker enforcement, and 110-column rendering. Prove symlink and FIFO rejection on each
  supported platform rather than assuming `Ada.Directories.Kind` follows links safely.

## Resolution and freeze state

The ownership and authority design above resolves the first-cycle P1 findings. The Type IR task has proposed a root
limited checked-document API, a separate offline-support crate, and an extractor-owned
`Production_Checked_Document`; serde requested an explicit empty-on-failure contract and exactly-once codec-limit
units before that API freezes.

Implementation may proceed for consumer-owned code that does not guess or duplicate Type IR. Binding and the
production source mode remain blocked until a reviewed post-`460e125` Type IR commit publishes the concrete Ada
API. That dependency will be pinned exactly and its nested Alire lock will be committed. A second independent
P0/P1/P2 diff review is mandatory after implementation; every P0 and P1 and any practical P2 must be fixed before
the Ada path becomes authoritative.

## Architecture correction cycles

Three additional read-only cycles challenged the target documentation and normative v2 schema. Findings covered
current-versus-future implementation claims, private production authority, user-unit dependencies, the exact
seven-line migration comparison, platform-independent provenance, closed source and dependency identities,
dependency content hashing, manifest and header grammar, fixture/authority coupling, exact artifact pairing,
marker enforcement, failure cleanup, and per-codec resource charging.

The corrected design now has:

- an explicit baseline status and fail-closed external dependency gate;
- fixture-only consumer-shape versus nonfixture production authority enforced by schema and verifier;
- a closed, domain-separated generator source identity with reproducible registry and Git content digests;
- a strict canonical v2 manifest/header contract and exact two-artifact profile;
- a platform-independent golden manifest with toolchain execution attestation kept in CI;
- independent Type IR, overlay, render, diagnostic, and aggregate-work resource ownership; and
- best-effort cleanup with manifest-last completion and no alteration of pre-existing paths.

After the final corrections, all three reviewers independently reported P0 none, P1 none, and P2 none. This freezes
the target architecture only. The new Ada scaffold and every later implementation increment receive their own
change review, and the Type IR API blocker remains in force.

## Overlay-loader implementation cycle

The first Ada consumer-owned slice uses the reviewed unrestricted JSON fork and SHA-256 crate only in the nested
generator. An independent review found no P0 issue and identified operation-local work counters, premature key-node
charging, unchecked cleanup, name-based special-file input, implementation-error misclassification, CLI-owned
limit defaults, missing compiler closure, and boundary-test gaps. The revision replaces those seams with one
noncopyable operation budget, recursive accepted-value accounting, bounded key-comparison work, transactional
owner replacement, primary-preserving nonraising discard, explicit caller-supplied CLI limits, and exact-boundary
tests.

One C file remains as narrow ABI leaves solely because `O_NOFOLLOW`, `O_CLOEXEC`, `O_NONBLOCK`, `S_ISREG`, and the
layout of `struct stat` are defined by platform headers. One leaf opens with the header-defined flags and one reports
the retained descriptor's `fstat`/`S_ISREG` result. Ada decides acceptance and owns all reads, byte and work charging,
status policy, close verification, and cleanup. No state machine, retry, allocation, parsing, hashing, or publication
logic is movable to SPARK within those leaves. Symlink, FIFO, and directory tests exercise the retained boundary on
every supported CI platform.

Two independent fix re-reviews then found P0 none, P1 none, and P2 none. The final verification used a forced-clean
Alire generator build, a forced-clean scaffold-test build, the smoke suite, all twelve transitional Python tests,
the runtime and generated-fixture test crates, release-marker and manifest checks, APM's ten audit checks, the
closed provenance enumeration, the 110-column Ada scan, and `git diff --check`. The reviewed Type IR Ada authority
and query API is still unpublished, so this checkpoint remains a fail-closed consumer-owned loader rather than an
authoritative generator cutover.
