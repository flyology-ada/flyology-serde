# Adapter combinator review — 2026-08-23

Scope: exact integer adapters, UTF-8 text validation, lossless optional composition, and array traversal/builders.

## Findings resolved

- P1: scalar decode used `out` candidates, which could publish an unspecified value after a reported failure. Scalar
  candidates are now `in out` and change only after successful range validation.
- P1: optional adapters could emit before learning that a backend conflates presence states. They require
  `Lossless_Optionals` before the first event or candidate mutation.
- P1: array decoding did not compare the actual item count with a known declared length. It now rejects a mismatch
  before finishing the candidate.
- P2: UTF-8 lookahead used index addition that could overflow before detecting truncation. Validation now checks
  remaining length first and rejects truncated, overlong, surrogate, and out-of-range sequences without allocation.
- P2: integer conversion could silently narrow. Generic signed and modular adapters compare exact positions before
  converting and return `Unsupported_Value` or `Out_Of_Range`.

## Ownership and publication

Serialization borrows source elements for one call. Array and optional decode procedures mutate only an unpublished
outer transaction candidate. Builder hooks own storage and rollback; the generic traversal performs no allocation
and retains no source slice.

## Verification

- `gnatformat` completed for changed Ada sources and tests.
- `alr build` passed without adapter warnings.
- `alr -C tests run` passed with malformed UTF-8, array, optional, scalar, and budget assertions enabled.
- Final staged-diff review is required before commit.
