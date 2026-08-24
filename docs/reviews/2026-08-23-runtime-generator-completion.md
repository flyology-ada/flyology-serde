# Runtime and generator completion review — 2026-08-23

Scope: serialization lifecycle and preflight, new bounded adapters, handwritten ownership fixtures, the initial
fixture-gated Type IR consumer, generated builder publication, manifest closure, CI integration, and the offline
sharing boundary with `flyology-wire` and `flyology-type-ir`.

## Decisions reviewed

- Serialization uses a nonemitting Counting traversal before the identical real traversal. Capabilities and
  explicit limits determine semantic acceptance; only operational storage or sink failures can first occur in the
  real pass.
- Serializer state is Ready, Active, Finished, or Poisoned. Finished output is immutable, prelatched status is a
  strict no-op, Abort revokes publication and poisons, and Reset is the only recovery operation.
- Deserialization builders retain candidates privately and publish only after exact document completion. Rollback
  is nonraising and releases controlled ownership after every status or exception.
- The runtime does not depend on Libadalang, Type IR, wire codecs, or a shared traversal protocol. The only proposed
  shared offline seam is Type-IR-owned dependency attestation, isolated exact-byte checker import, same-read
  `load_checked`, and fixture/profile identity gating.
- The initial generator accepts only the exact reviewed fixture profile. Strict production remains explicitly
  closed while Type IR v1 lacks a mandatory record-predicate fact and its extractor emits no admissible document.

## First independent cycle

Three read-only reviewers inspected the complete uncommitted tree.

- Serialization/CBOR architecture: P0 none, P1 one, P2 three.
- Runtime and ownership coverage: P0 none, P1 none, P2 five.
- Type IR consumer and generator: P0 none, P1 seven, P2 seven.

The runtime P1 was an underspecified abstract serializer lifecycle. The generator P1s covered closed Ada context,
Ada-safe names and lines, incomplete generic and record-predicate exclusion, manifest entry closure, compilation
binding, atomic no-clobber publication, and the missing review record. All were resolved before the second cycle.

The P2 resolutions add exact limit and capability boundaries, injected preflight/sink/finish failures, immutable
second-finish behavior, reset/reuse, constrained-array and map rollback edges, a private controlled builder,
discriminated failure preservation, a documentary-schema authority statement and closer bounds, immutable lowering,
exact generator-source identity, complete fixture/nonfixture manifest validation, and narrowed diagnostic claims.

## Second independent cycle

The corrected tree received a second read-only P0/P1/P2 review by the same three independent reviewers. Adversarial
generator probes found two remaining P1s: escaped maximum-length names could exceed 110-column Ada, and generator
provenance hashed a later reread rather than the executed bytes. The CLI now executes a same-read, isolated copy of
`generator_impl.py`, and the loader rejects escaped literals that cannot fit every generated line. Follow-up P2s
added an injected preflight-status regression and direct non-regular manifest-entry tests.

After those corrections, all three reviewers independently reported:

- P0: none.
- P1: none.
- P2: none.

The generator reviewer also confirmed that the only justified shared offline surface remains dependency
attestation, isolated exact-byte checker import, same-read `load_checked`, and fixture/profile gates. Consumer
overlays, lowering, Ada naming and rendering, artifacts, builders, and runtime traversal remain project-owned.

## Verification before second review

- Forced root library and assertion-enabled test builds succeeded.
- The runtime test executable exited normally.
- Twelve Python generator tests passed.
- The closed manifest verifier and fixture-marker scan passed.
- The generated Ada JSON and CBOR round-trip executable passed after its Alire pre-build manifest verification.
- `git diff --check` and the 110-column scan over handwritten and generated Ada passed.
- All ten APM audit checks passed with no drift.

GNATformat is unavailable in this environment. Compiler style checks and the explicit line-length scan are used for
handwritten Ada.
