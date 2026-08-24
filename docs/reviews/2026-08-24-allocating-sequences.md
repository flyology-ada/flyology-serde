# Allocating sequence architecture and implementation review

Status: accepted after architecture, implementation, and fix re-review.

## Decision

`Adapters.Allocating_Sequences` is a generic standard-heap vector candidate for definite, nonlimited, copy-safe
elements. It uses the operation decode policy as its construction limit, stages every element in a local vector,
requires complete sequence traversal, and moves into the exclusively owned unpublished target only after
`End_Sequence`. The backend remains the sole decode-budget owner; adapter capacity comparisons add no charges.

Known and observed lengths are checked by discrete positions before conversion or element callbacks. Local
`Reserve_Capacity` and `Append` `Capacity_Error` become `Capacity_Exceeded`; `Storage_Error`, callback exceptions,
and final `Move` exceptions propagate for root abort and rollback. Append may copy and Adjust an element, so limited,
move-only, identity-owning, and otherwise non-copy-safe resources remain on the existing builder/handwritten seam.
Standard-vector reserve and growth may also initialize and finalize spare capacity or copy existing elements, so
copy-safe controlled types must maintain ownership under those operations and may retain initialized spare values.

## Proposal review

Independent review reported P0 none. Three P1 requirements were incorporated before implementation: portable
pre-callback capacity checks, a `Capacity_Error` handler restricted to local candidate operations, and an explicit
copy/finalization ownership contract with lifecycle tests. P2 recommendations added explicit element equality,
`Unsupported_Value` for an unrepresentable serialization length, proportional-reserve and `Storage_Error` prose,
exclusive target ownership, retained index-path tests, indefinite limit coverage, and root rollback coverage.

## Implementation review

The independent implementation review found P0 none and P1 none. Its P2 findings were all fixed: definite CBOR now
proves known over-limit rejection before an element callback; serialization tests prove prelatched no-op and retained
index paths; JSON length wording is exact; and the controlled contract and tests allow implementation-dependent
initialized spare capacity while proving cleanup to the prior baseline and then zero.

The narrow re-review reported P0 none, P1 none, and P2 none. A forced warning-visible root rebuild, the complete
assertion-enabled test rebuild and executable, the 110-column Ada scan, and `git diff --check` pass. GNATformat is not
available in the configured toolchain; compiler style checks and the explicit scan cover the changed Ada sources.
