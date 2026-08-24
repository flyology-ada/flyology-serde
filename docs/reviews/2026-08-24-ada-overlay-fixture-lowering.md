# Ada overlay fixture-lowering review

Status: accepted after architecture, implementation, and narrow fix review.

Scope: the nested Ada generator's test-only lowering from a checked serde overlay into the already reviewed bounded
record model and in-memory renderer. Production Type IR authority, headers, manifests, publication, and CLI success
remain out of scope and fail closed.

## Architecture review

The proposal retained the fixture child exclusively below `tools/generator/ada/tests/src`, required the exact
reviewed Type IR v1 fixture commit/source/semantic identities and canonical binding graph, and assigned only logical
and presentation names and runtime limits to the overlay. The lowerer shares the overlay-loading operation budget
and adds one separate semantic acceptance charge for the record and each of three fields.

Independent review reported P0 none. Two P1 conditions were incorporated before implementation: stage every query in
fixed nonlimited scratch so failure returns a default-empty limited model, and compare every reported length with the
model's intrinsic capacity before copying into a fixed buffer. One P2 request added a valid alternate overlay that
changes every overlay-owned policy family and proves those values reach the model and rendered payload. The reviewer
accepted exact byte spelling only for this canonical test fixture; future production Type IR lowering retains Ada's
case-insensitive semantic identity rules.

## Change review

The first independent implementation review reported P0 none and one P1. The output unit had initially been treated
as overlay policy even though the pinned Type IR fixture attests visibility for consumer unit
`Flyology.Generated`. The structural gate now requires that exact context, the alternate policy fixture retains it,
and a direct wrong-context test proves unsupported, unpoisoned, default-empty rejection.

Three P2 evidence requests were also fixed. Tests now observe every public field family of failed models and require
the default-empty value; a canonical overlay containing a 130-byte component ID proves capacity rejection before
copy without poisoning; and a prelatched diagnostic is tested both with a clean and an already poisoned budget.

The mandatory narrow fix re-review reported P0 none, P1 none, and P2 none. It found no regression in fixed staging,
charge accounting, structural binding gates, policy propagation, test-source isolation, renderer transactionality,
or the production CLI's fail-closed behavior.

A second independent whole-diff review then reported P0 none, P1 none, and P2 none. It verified the exact fixture and
output-context gates, default-empty publication, exact and one-less charging, canonical policy fixture, adversarial
failure cases, test-project isolation, and unchanged production/runtime/Type IR/Wire boundaries.

## Verification

The root build and Ada tests, a forced warning-visible nested generator test build and smoke suite, all 12 Python
generator tests, generated-fixture build/run, release-marker and manifest checks, APM 0.28.0's 10 checks, staged diff
check, and the explicit 110-column scan pass. `gnatformat` is not installed in the configured host or toolchain;
the owning-project compiler style checks and explicit scan provide the available formatting evidence.
