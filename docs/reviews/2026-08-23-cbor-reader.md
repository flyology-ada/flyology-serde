# CBOR reader implementation review — 2026-08-23

Scope: bounded pull decoding, CBOR syntax, typed logical envelopes, scalar fidelity, copied ownership, resource
accounting, failure lifecycle, documentation, and executable conformance coverage.

## Review rule

The implementation received independent adversarial review before commit. Every P0, P1, and P2 finding was fixed
and re-reviewed. The final reviewer verdict was P0 none, P1 none, P2 none, with commit clearance.

## Findings resolved

- P1: an indefinite present optional could expose a closing break as a child and report the wrong status. Child
  availability is now validated before publication; a legal early envelope break reports `Invalid_Value`.
- P1: sequence, map, optional, record, and variant traversal could publish or charge an item before confirming the
  required child head or record value existed. Each affected transition now validates syntax before availability,
  item accounting, or output publication. Map key completion also validates the value head.
- P2: standalone breaks and unsupported major-type-7 simple values produced entry-point-dependent statuses. A common
  typed surface classifier now reports `Syntax_Error` for misplaced breaks and `Unsupported_Value` for unsupported
  simple values.
- P2: the documentation still described the reader as planned and overstated structural prechecks. It now describes
  the implemented checkpoint and distinguishes unsigned-domain narrowing checks, configured limits, caller
  capacity, payload bounds, and traversal-time child validation.
- P2: the initial tests did not cover the full documented matrix. Coverage now includes signed and unsigned
  boundaries, shorter floats and all nonfinite categories, both zero signs, duplicate map delivery, definite and
  indefinite typed envelopes, tag and cardinality precedence, nonpreferred and oversized lengths, string chunk
  grammar, malformed heads and payloads, caller capacities, all budget dimensions, raw-skip limits, nested failure
  poison/unwind/reset, and non-1 source lower bounds.

## Accepted contracts

- The reader borrows immutable input and copies all text, bytes, names, and alternatives into caller-owned buffers.
  No source slice escapes an operation.
- One backend-owned budget charges consumed input bytes, accepted logical values, logical container items, and text
  or byte lengths exactly once under the documented rules.
- Any failure latches the primary error, unwinds budget scopes, poisons the reader, and requires `Reset` before reuse.
- Typed reads reject semantic tags. `Skip_Value` accepts a bounded, well-formed tag wrapper so an adapter can discard
  an unknown field without interpreting tag semantics.
- CBOR traversal, envelopes, capabilities, float categories, budgets, and diagnostics remain serde runtime concerns.
  They add no dependency or runtime protocol shared with Flyology wire or Type IR.

## Verification

- Forced clean `gprbuild -f` completed without warnings.
- The assertion-enabled test executable completed successfully.
- `git diff --check` and the 110-column Ada scan passed.
- `apm audit --ci --no-policy` passed all 10 checks.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
