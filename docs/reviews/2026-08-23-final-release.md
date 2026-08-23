# Whole-repository release review — 2026-08-23

Scope: the complete format-agnostic traversal API, JSON and CBOR backends, bounded and allocating modes,
transactional construction, adapters, derivation and Type IR boundaries, documentation, tests, and release CI.

## Review rule

An independent whole-repository adversarial review used P0 for catastrophic, security, or unrecoverable corruption;
P1 for a release-blocking contract or correctness defect; and P2 for a lower-risk but actionable API,
documentation, or verification defect. The first sweep found P0 none, P1 two, and P2 four. Every finding was fixed
and re-reviewed. The final verdict was P0 none, P1 none, P2 none, with release clearance.

## Findings resolved

- P1: JSON raw subtree skipping bounded only raw syntax depth, allowing an ignored value to exceed the nesting limit
  when entered beneath an active logical scope. Its overflow-safe check now combines active budget depth with raw
  depth. A record-at-limit regression proves an ignored container fails with `Depth_Exceeded`.
- P1: JSON output accessors exposed incomplete or failed prefixes. Bounded `Copy_Output` now reports
  `Invalid_State`, length zero, and no prefix unless the writer is complete. Allocating `Output` returns an empty
  string until completion. Tests cover bounded capacity failure and allocating incomplete and grammar failure.
- P2: the JSON overview described binary64 without excluding unsupported nonfinite categories. The mapping table and
  capability prose now explicitly cover finite binary64 values.
- P2: JSON mislabeled unconfigured allocating-writer heap exhaustion as `Capacity_Exceeded`. Mutation now poisons
  the writer and propagates `Storage_Error`, matching CBOR. A result-copy allocation failure propagates while leaving
  an already-completed writer retryable.
- P2: the static serialization root invoked application code despite an already-latched error. It now makes that
  call a strict no-op, with a side-effecting-hook regression proving no hook call or backend event occurs.
- P2: only APM resources had maintained CI. The Ada workflow now pins Alire, GNAT, GPRbuild, and action revisions and
  builds the library plus assertion-enabled test crate on macOS and Ubuntu.

## Verification

- A forced warning-visible rebuild of the complete library succeeded.
- A forced assertion-enabled rebuild of the complete test project succeeded, and the test binary exited normally.
- Independent review verified that the rebuilt binary was newer than every changed Ada and test source.
- `git diff --check`, the 110-column scan across all handwritten Ada, and all ten APM audit checks passed.
- The final implementation, documentation, and workflow re-review reported P0 none, P1 none, and P2 none.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
