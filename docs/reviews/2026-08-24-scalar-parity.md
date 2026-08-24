# Scalar format-parity review

Status: accepted after proposal, implementation, and narrow fix re-review.

## Scope

This test-only tranche adds direct evidence for the existing modular-integer adapter and expands JSON binary64
round-trip evidence. It changes no runtime API, backend, Type IR boundary, or wire behavior.

Successful unsigned endpoint and JSON finite-float round trips use root adapters so counting preflight, writer and
reader document finish, candidate commit, and exact-root validation all run. Direct narrow-modular tests isolate
`Out_Of_Range` target preservation. A same-reader retry proves prelatched no-op behavior, and an explicit trailing
JSON token proves rollback retains the prior published float.

Binary64 fixtures are created from explicit 64-bit patterns and compared by inverse bit conversion; the test asserts
the target's size, mantissa, and exponent attributes before using the established test-only unchecked conversion.
It does not depend on JSON decimal spelling or host endianness.

## Proposal review

Independent review reported P0 none and P1 none. Its P2 requirements—root success paths, exact binary64 attributes,
both adjacent values around one, sufficient output capacity, direct leaf overflow preservation, prelatched evidence,
and real trailing-input rollback—are incorporated.

## Implementation review

The implementation review reported P0 none and P1 none. Its P2 findings were fixed by adding mod-256 zero
serialization and decode through both formats and correcting exponent-operator spacing. The narrow re-review reported
P0 none, P1 none, and P2 none. The assertion-enabled suite, 110-column Ada scan, and `git diff --check` pass.
GNATformat was invoked through the owning Alire project but is not installed in the configured toolchain; compiler
style checks and the explicit scan cover the new test sources.
