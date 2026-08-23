# Initial architecture review — 2026-08-23

Scope: the first bounded serde contracts, counting backend, derivation boundary, and Type IR coordination.

## Findings resolved

- P1: container close operations did not verify the matching begin kind. The counting backend now maintains a
  bounded kind stack and reports `Invalid_State` for mismatches.
- P1: tests used `pragma Assert` without enabling assertions. The test project now uses `-gnata`.
- P1: serializer container lengths were always known. Sequence and map begins now accept optional length
  information for streaming JSON and indefinite-length CBOR.
- P1: deserialization could mutate a published value before the traversal succeeded. The generic adapter now uses
  begin, commit, and rollback hooks and rolls back every reported or exceptional failure.
- P1: scalar events could imply lossy conversion. Binary64 is explicit, and generation rejects every scalar that
  cannot be represented exactly by the current 64-bit integer or binary64 capabilities.
- P1: resource, unknown-field, duplicate, missing, alias, and lookup behavior was implicit. Bounded decode and
  record policies plus generated-local lookup rules are now explicit.
- P1: future borrowed slices had no lifetime rule. The bounded API currently copies into caller buffers; any future
  zero-copy view is callback/step-scoped and may not be retained.
- P2: event ordering and map-key behavior were underspecified. The event grammar is now normative in the
  architecture document.
- P2: input offset units were ambiguous. Each error now identifies byte, code-unit, code-point, or unknown units.
- P2: truncated error-path names were not marked. `Name_Truncated` now preserves that diagnostic fact.
- P2: the counting backend did not validate field/value alternation or declared item counts. It now checks the full
  event grammar and reports counter overflow instead of relying on a constraint exception.

## Accepted boundaries

- No serde or wire runtime dependency is shared. The common layer is the offline extractor and versioned structural
  Type IR; logical event lowering remains backend-specific.
- The first milestone supplies contracts and a validation backend, not a JSON or CBOR implementation.

## Final-cycle gate

All P0 and P1 findings must be closed. P2 findings are fixed unless a later review records an explicit acceptance.
Formatting, build, tests, and a final staged-diff review are required after the fixes above.
