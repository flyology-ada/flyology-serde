# Allocating map review

Status: accepted.

## Scope

This tranche adds a standard-heap `Ada.Containers.Ordered_Maps` candidate for
definite, nonlimited, copy-safe keys and values. It also adds map-specific
duplicate handling to `Decode_Policy`. It changes no backend grammar, budget
ownership, Type IR fact, wire identity, or runtime dependency boundary.

Comparator equivalence is logical key equality. Serialization uses comparator
order. Deserialization stages a complete local map and moves it into an
unpublished target only after exact traversal and `End_Map`. Backends preserve
source pairs; the adapter rejects duplicates, keeps the first pair, or keeps
the first key object while replacing its value.

## Proposal review

The architecture review reported P0 none. Its P1 requirements fixed comparator
semantics, portability and capacity gates, capability preflight, candidate
transactionality, exception propagation, and controlled ownership. Its P2
requirements fixed ordered traversal, JSON pair representation, target cursor
exclusion, and the required cross-format and failure matrix.

## Implementation review

The implementation review reported P0 none and P1 none. It reported six P2
groups: duplicate key/value observation used an unnecessary key copy; one body
block needed normal indentation; two limit tests used an unsupported looser
backend policy; status/exception modes were incomplete; prelatched and
pre-populated replacement cases were absent; and public documentation/review
records were absent. All findings are addressed in the current diff. A narrow
fix review reported P0 none, P1 none, and P2 none.

A final test-hardening change replaced an allocating case-fold comparator with
the ordinary nonallocating text comparator. Identical text keys cover duplicate
policy in both formats; distinct comparator-equivalent controlled keys prove
first-key retention. Its narrow review initially requested naming and comment
clarity; the final confirmation reported P0 none, P1 none, and P2 none.

## Verification

- `alr build`
- `alr -C tests run`
- `apm audit --ci --no-policy`
- 110-column scan of changed Ada files
- `git diff --check`

`gnatformat` was invoked through `flyology_serde.gpr`, but the configured
toolchain does not provide that executable. The compiler's configured style
checks and the explicit line-length scan are the formatting fallback.
