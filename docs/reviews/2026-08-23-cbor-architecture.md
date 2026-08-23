# CBOR architecture review — 2026-08-23

Scope: logical-to-CBOR mapping, deterministic-encoding claims, typed envelopes, bounded/allocating ownership,
reader acceptance, budget accounting, and separation from Flyology wire semantics.

## Review rubric

- P0: the mapping necessarily corrupts values, creates an unsafe ownership boundary, or couples serde and wire.
- P1: a supported logical value is not lossless, malformed input can bypass a required bound, or the proposed event
  grammar cannot be implemented without ambiguity or partial publication.
- P2: a standards acceptance rule, diagnostic, determinism statement, or test obligation is underspecified.

Every P0 and P1 must be fixed before implementation. P2 is fix-by-default. The post-implementation review must
revisit this mapping against the code, malformed fixtures, golden bytes, and round-trip tests.

## Initial decisions for review

- Use only RFC 8949 core data items; allocate no private semantic tag numbers.
- Preserve optionals and variants with typed structural envelopes.
- Preserve binary64 categories by emitting binary64; accept exact promotion from shorter CBOR floats.
- Use definite lengths when known and indefinite arrays/maps only for unknown logical container lengths.
- Keep syntax traversal, byte offsets, resource budgets, and poison/reset in the backend, with candidate publication
  remaining an adapter responsibility.
- Make no deterministic-CBOR claim and no Flyology wire-format claim.

## Findings

### Findings resolved before implementation

- P1: the first draft promised exact binary64 representation, exceeding the logical contract for NaN payload and
  signaling state. The contract now promises exact finite values, infinity and signed-zero preservation, and only
  the NaN category.
- P1: nonnegative signed values share major type 0 with unsigned values. Signed read/write symmetry, range checks,
  and the surface-only `Peek_Kind` convention are now explicit.
- P1: raw skip traversal did not define accounting for tags, chunks, and representation wrappers. Syntax depth now
  includes every tag and container, while items include array children, map pairs, and indefinite-string chunks.
- P1: hostile 64-bit arguments could be narrowed before validation. The design now requires unsigned-domain checks
  against every relevant limit and extent before conversion or index arithmetic.
- P1: indefinite-string pre-scans lacked a work contract. Any pre-scan is bounded by remaining input, never moves or
  charges the cursor, and is followed by one charged pass, keeping total work linear with a fixed multiplier.
- P1: writer failure behavior was missing. Both bounded and allocating writers now poison and suppress incomplete
  output after every failure, require reset, and define allocation-failure propagation and discard behavior.

- P2: optional and variant representations now define definite and indefinite acceptance, unsigned discriminators,
  exact cardinality, and payload-map requirements.
- P2: indefinite strings now require definite same-major-type chunks and independently valid UTF-8 text chunks.
- P2: logical-value and container-item charging now gives exact units for sequences, maps, records, variants, and
  present optionals, while distinguishing representation wrappers and chunks.
- P2: every application-map pair is delivered in source order; adapters own key equivalence and duplicate action,
  with rejection recommended, and record aliases use record duplicate policy.
- P2: `Peek_Kind` now has an exhaustive surface mapping and expressly performs no numeric or typed coercion.
- P2: typed operations reject every semantic tag with `Unsupported_Value`; bounded skip validates only basic CBOR
  structure, not unknown tag semantics.
- P2: shortest head arguments are described as a local preferred-serialization rule, not a claim that complete
  output is preferred or deterministic.
- P2: the borrow contract excludes mutation through any alias or task and defines offsets relative to the first
  source element rather than the Ada lower bound.
- P2: the backend's all-true capabilities are stable for an operation, and capability failure precedes output or
  destination mutation.
- P2: allocating source ownership and destination construction remain explicit owning facades; the pull reader does
  not lend slices.
- P2: the required golden, malformed, boundary, resource-limit, and reset/unwind cases are now listed as a
  conformance matrix.

The final freeze review exposed and resolved two additional P1 and two P2 issues:

- P1: raw skip depth now composes with the active logical depth instead of receiving an independent allowance.
- P1: scalar unsigned arguments remain full-width `Unsigned_64`; only structural lengths, counts, and indices are
  checked against `Natural'Last` before narrowing.
- P2: the contract disclaims whole-output preferred serialization as well as deterministic encoding.
- P2: malformed CBOR reports `Syntax_Error`, while well-formed but incompatible or invalid typed envelopes report
  `Unexpected_Kind` or `Invalid_Value` respectively.
- P2: semantic-tag rejection takes precedence over envelope kind diagnostics, and legal premature termination of an
  indefinite envelope is distinguished from a syntactically misplaced break in a definite item.

### Preimplementation disposition

Across all passes, the independent review found no P0, eight P1, and fifteen P2 issues. All are resolved in the
architecture contract.
The wire and Type IR separation remains intact: CBOR envelopes, capabilities, budgets, and traversal are serde-only
runtime concepts.
