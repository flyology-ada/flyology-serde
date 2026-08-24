# Allocating byte portability review

Status: accepted after implementation and fix re-review.

## Problem

`Adapters.Allocating_Bytes.Deserialize_Candidate` converted the caller's `Natural` byte limit directly to
`Stream_Element_Offset`. A target with a narrower stream index range could therefore raise `Constraint_Error` before
the reader reported a serde status. The accepted length was also converted directly to `Count_Type`.

## Decision

The adapter checks both target representations before conversion. An unrepresentable configured maximum is
`Capacity_Exceeded` before the candidate or input is touched. An unrepresentable accepted vector length is also
`Capacity_Exceeded`. Existing prelatched-status and candidate cleanup behavior is unchanged.

The regression test executes the extreme-limit path on targets where `Natural` is wider than
`Stream_Element_Offset`; it then decodes again from the same reader under a representable maximum to prove that the
rejection consumed no input. The source-level guarded conversion and normal target builds cover the common
equal-or-wider stream-index case.

## Review record

The independent implementation review reported P0 none, P1 none, and one P2 evidence gap: the initial regression
proved status and candidate preservation without proving input preservation. The same-reader retry closes that gap.
The final diff has P0 none, P1 none, and P2 none. The root build, assertion-enabled suite, 110-column scan, and
`git diff --check` pass.
