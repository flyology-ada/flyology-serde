# Root abort and unwind review — 2026-08-23

Scope: failed root-operation cleanup, budget-scope unwind, backend poisoning, candidate rollback ordering, primary
status and exception preservation, documentation, and executable JSON/CBOR integration coverage.

## Review rule

Architecture and implementation received independent adversarial review. Every P0, P1, and P2 finding was fixed
and re-reviewed. The final verdict was P0 none, P1 none, P2 none, with commit clearance.

## Findings resolved

- P1: an adapter status or exception could leave a format backend's traversal and budget scopes open because only
  backend-detected failures performed unwind. The abstract, root-only `Abort_Document` operation is now nonraising
  and idempotent. It unwinds every open backend scope, clears logical frames, revokes document completion, and
  poisons reuse until reset.
- P1: cleanup order could otherwise publish or retain a partially built value. A root transaction now calls abort
  before candidate rollback on every post-begin status or exception. Commit remains the only publication point.
- P2: initial tests did not prove exact diagnostic preservation. The status path now verifies that abort attaches
  the exact backend byte offset and unit while retaining an existing field path and primary application status.
- P2: merely catching an exception did not show that cleanup preserved it. Tests now compare the original adapter
  and commit exception messages after abort and rollback.
- P2: commit failure after successful document finishing needed explicit coverage. Reported and raised commit
  failures now verify revoked completion, rollback without publication, backend poison, and primary failure
  preservation.

## Accepted contracts

- `Abort_Document` is a root-transaction cleanup operation, not a nested traversal event. It must not raise or
  replace an already latched status, and repeated calls have the same poisoned end state.
- A backend may unwind its own scopes when it detects a failure. Root abort additionally closes scopes left open by
  application adapter failure. Every successfully entered budget scope is left exactly once.
- A poisoned reader rejects further traversal until its explicit `Reset` establishes a fresh cursor, frame stack,
  completion state, and budget.
- Candidate rollback runs after backend abort and must leave the previously published application value unchanged.

## Verification

- A forced full warning-visible library and assertion-enabled test rebuild completed successfully.
- The complete test binary ran successfully.
- Tests cover status and exception failure inside open JSON and CBOR sequences, exact path/offset preservation,
  idempotent abort, poison-before-reset, successful reset reuse, and status/exception failure during commit after
  successful document finishing.
- `git diff --check`, the 110-column Ada scan, and the complete APM policy audit passed.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
