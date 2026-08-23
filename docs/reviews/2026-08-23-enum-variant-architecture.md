# Enumeration and finite-variant architecture review — 2026-08-23

Scope: generated enumeration mappings, finite named variant alternatives, discriminated-record lowering, global
field identity, candidate ownership, nullary representation, error paths and offsets, runtime boundaries, and the
required implementation proof matrix.

## Review rule

The proposed architecture received independent adversarial review. Every P0, P1, and P2 finding was incorporated
and re-reviewed. The final verdict was P0 none, P1 none, P2 none, with clearance to freeze and implement.

## Decisions

- Enumeration metadata has independent total-literal, type-name, literal-name, and per-literal alias bounds. Checked
  local tables iterate enumeration declarations without using representation values or positions.
- Declared primary names and aliases must map uniquely to their own literal or alternative. Handwritten matchers may
  accept undeclared extra names, as record matchers do; runtime full scans reject ambiguity.
- Variants independently bound total alternatives, total global field declarations, and fields belonging to one
  alternative. Every global field declaration must belong to at least one alternative.
- One ordinal identifies one logical field declaration. Common declarations reuse it across leaves; distinct branch
  declarations remain distinct despite equal spelling. Name uniqueness is checked within each selected alternative,
  and filtered global ordinal order controls serialization and missing handling.
- `Begin_Alternative` stages only unpublished candidate state and must leave rollback valid after any status or
  exception. Replacement has the same strong ownership contract as records. Final validation runs after
  `End_Variant` and selected missing hooks and constructs or checks the exact discriminant path.
- An overlay cannot change Known discriminant/default facts, override mandatory Unknown or Unsupported facts, or
  grant visibility. Physical representation and summarized Libadalang shapes do not select alternatives.
- Error paths gain a typed `Alternative_Element`. Decode retains the incoming constructor spelling, including an
  alias, above incoming field spellings; missing fields use the canonical field beneath that alternative.
  Enumeration literal text is scalar content and does not become a structural path element.
- Adapter semantic errors receive the backend's current next-unread offset and unit during mandatory root abort.
  The interface cannot promise token-start offsets.
- A zero-known-field alternative still traverses all supplied fields under unknown reject/skip policy. A distinct
  nullary-variant combinator preserves the logical variant envelope; enum lowering is explicit overlay policy only.

## Required implementation evidence

- Enumeration primary/alias success, no-match and ambiguity, metadata failure before events/input, and a
  nonmonotonic representation-clause fixture.
- Alternative aliases, unknown and ambiguous constructors before builder mutation, common fields, disjoint
  same-spelled fields, unused/global/per-alternative bounds, and selected-only missing order.
- Zero-field unknown reject and nested-value ignore, plus exact JSON and CBOR all-nullary envelopes.
- Unknown and duplicate field policies with exactly-once skips, ownership-counted begin/replacement/final failures,
  discriminant mismatch, typed and truncated paths, and JSON/CBOR malformed-envelope precedence.
- No runtime dependency on Type IR, Libadalang, wire codecs, or wire policy.
