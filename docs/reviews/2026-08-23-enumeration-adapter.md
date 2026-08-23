# Bounded enumeration adapter review — 2026-08-23

Scope: representation-independent logical enumeration names, aliases, metadata bounds, candidate assignment,
semantic diagnostics, JSON/CBOR behavior, documentation, and executable conformance coverage.

## Review rule

Implementation received independent adversarial review. Every P0, P1, and P2 finding was fixed and re-reviewed.
The final verdict was P0 none, P1 none, P2 none, with commit clearance.

## Findings resolved

- P1: representation values or positions could otherwise leak into traversal. The adapter builds a checked local
  table in declaration order and uses only canonical logical names. A legal ordered, non-default, noncontiguous
  representation clause proves output and decode do not depend on `Enum_Rep` or `Pos`.
- P1: alias metadata could be ambiguous or asymmetric. Preflight bounds counts and lengths, validates UTF-8, rejects
  duplicate declared names, and proves every declared name matches exactly its own literal before a typed read or
  output event. Runtime still full-scans handwritten matchers and rejects extra-name ambiguity.
- P1: a failed match could mutate the candidate. Assignment now occurs only in the exactly-one-match branch. Direct
  candidate tests prove no-match, ambiguity, and incoming capacity failure retain the previous value.
- P2: root rollback tests could mask premature mutation and offset behavior. Direct tests prove semantic failures
  leave `Unknown_Offset`; mandatory root abort later attaches the backend's current next-unread byte position while
  retaining the enclosing structural path.
- P2: metadata coverage now includes total literals, alias count, type/literal/alias length, invalid UTF-8,
  duplicate primaries, cross-literal aliases, and matcher no-match, all before serializer events or input consumption.

## Accepted contracts

- Declared names are authoritative overlay metadata. A handwritten matcher may accept extra names, but every runtime
  name must resolve uniquely. No match is `Invalid_Value`; ambiguity is `Application_Error`.
- Literal text is scalar content and is not inserted into `Error_Info` as a field or alternative path. The enclosing
  structural path and backend input offset identify the failed value.
- `Deserialize_Candidate` changes its target only after one literal resolves. Malformed, wrong-kind, over-capacity,
  invalid, and ambiguous input leave it unchanged.
- Ada enumeration representation clauses are ordered by language legality. The conformance fixture therefore uses
  legal ordered but non-default and noncontiguous values rather than an illegal nonmonotonic clause.

## Verification

- A forced full warning-visible library and assertion-enabled test rebuild completed successfully.
- The complete test binary ran successfully.
- JSON and CBOR tests cover canonical output and primary decode; JSON also covers aliases, no-match, ambiguity,
  backend kind precedence, next-unread offsets, incoming capacity, and metadata failure before input.
- `git diff --check`, the 110-column Ada scan, and the complete APM policy audit passed.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
