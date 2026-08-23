# CBOR writer implementation review — 2026-08-23

Scope: bounded and explicitly allocating CBOR writers, RFC 8949 output bytes, logical event grammar, failure
lifecycle, ownership, capabilities, and conformance tests.

## Findings resolved

- P1: text conversion declared an input-sized local byte array before failure handling. Large text could consume
  unbounded stack in bounded mode or raise an unpoisoned `Storage_Error`. UTF-8 is now validated first and copied
  through a fixed 256-byte buffer, retaining allocation-free bounded behavior and mutation-time poisoning.
- P2: the allocating-output copy was covered by wording intended for mutation failure. A failed `Output` allocation
  publishes nothing and leaves the completed writer retryable; an allocation failure while emitting still poisons
  before propagation.
- P2: the finite-value constructor now states its validity precondition explicitly, preventing an unchecked invalid
  IEEE representation from being presented as a semantic finite value.
- P2: tests cover every integer argument width, signed extremes, finite and nonfinite binary64 bytes, positive and
  negative zero behavior, exact text chunk-plus-tail emission, UTF-8, bytes, definite and indefinite containers,
  none versus some(null), nested optionals, records, variants, arbitrary map keys, depth, count and grammar errors,
  partial-event capacity failure, incomplete-output suppression, allocating output, and reset.
- P2: the backend document now identifies reader behavior and malformed-input cases as the planned normative
  contract rather than implying that the writer-only checkpoint already contains reader code and tests.

## Review disposition

The independent implementation review found no remaining P0 or P1. A final pass verifies the P2 wording and tests
before commit. CBOR reader acceptance and malformed-input behavior remain a separate implementation and review.
