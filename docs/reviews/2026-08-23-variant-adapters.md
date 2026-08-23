# Bounded variant adapters review — 2026-08-23

Scope: finite and all-nullary logical variant combinators, bounded metadata and lookup, selected field membership,
transactional construction, alternative-aware diagnostics, documentation, and JSON/CBOR conformance coverage.

## Review rule

Architecture and implementation received independent adversarial review. Every P0, P1, and P2 finding was fixed
and re-reviewed. The final verdict was P0 none, P1 none, P2 none, with commit clearance.

## Findings resolved

- P1: generated metadata, membership, name, selection, and matcher callbacks could otherwise change during an
  operation or allocate behind the bounded adapter. The generic contract now requires operation-stable,
  nonallocating functions, and metadata is checked before the first input consumption or output event.
- P1: a nullary builder contract did not initially make candidate ownership and rollback explicit. Both variant
  generics now require `Begin_Alternative` to stage only unpublished state and preserve outer rollback after a
  reported error or propagated exception. The nullary finish hook has the same obligation.
- P2: failure coverage now exercises nested ownership acquired by `Begin_Alternative`, both reported and exception
  failures, exactly-once root rollback, field replacement, parse failure, and final-candidate rejection.
- P2: metadata coverage now includes total alternatives, total fields, fields per alternative, unused global fields,
  and declared-name collisions, all before events or input consumption. Handwritten constructor ambiguity fails
  before `Begin_Alternative`; field-name ambiguity fails before its value is consumed or duplicate policy is applied.
- P2: JSON and CBOR fixtures now cover zero-field alternatives under reject and ignore policies, duplicate reject,
  keep-first and keep-last behavior, malformed envelope precedence, nullary variants, aliases, and typed paths.

## Accepted contracts

- One global ordinal identifies each logical field declaration. Common components retain one ordinal across leaves;
  same-spelled declarations in disjoint alternatives remain distinct. Names and aliases are presentation metadata,
  not Type IR identities or wire tags.
- A finite adapter serializes only the selected alternative's fields in global declaration order. Decode resolves
  one alternative, begins an unpublished candidate, consumes every supplied field exactly once, ends the variant,
  applies missing hooks in selected declaration order, and then validates the candidate.
- Runtime name ambiguity is `Application_Error` and wins before value consumption or duplicate handling. Unknown
  ignore and keep-first each skip exactly one complete value; keep-last invokes the field hook once with the strong
  replacement contract.
- An all-nullary sum retains a logical variant envelope with a zero-field payload. Mapping it to an enumeration is
  an explicit overlay decision, not an implicit runtime optimization.
- Error paths distinguish an `Alternative_Element` from a `Field_Element`. Names retain a bounded prefix and set
  `Name_Truncated`; root abort attaches the backend's current next-unread offset without replacing the path.
- The shared Type IR remains structural and offline. Serde's logical variant lowering and runtime traversal do not
  enter the wire runtime or grant an overlay authority to alter structural facts or visibility.

## Verification

- Independent review forced a warning-visible assertion-enabled test rebuild and ran the complete test binary.
- The primary release pass forced the full library and test projects and ran all tests successfully.
- `git diff --check`, the 110-column Ada scan, and the complete APM policy audit passed.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
