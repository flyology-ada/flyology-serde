# Bounded record adapter review — 2026-08-23

Scope: the format-agnostic bounded record combinator, generated metadata contract, policy ordering, ownership-safe
replacement, missing/default construction, final candidate validation, documentation, and JSON/CBOR integration.

## Review rule

Architecture and implementation received independent adversarial review. Every P0, P1, and P2 finding was fixed
and re-reviewed. The final verdict was P0 none, P1 none, P2 none, with commit clearance.

## Findings resolved

- P1: schema ordinals could otherwise index unbounded or arbitrary storage. The generic uses an independent positive
  `Maximum_Fields`, counts before its first event, and stores ordinals and seen bits only in local bounded tables.
- P1: declared primary and alias metadata could make serialization fail to deserialize. Preflight bounds counts and
  lengths, validates UTF-8, rejects duplicate declared names, and proves that each declared name matches exactly its
  own field. Decode still performs a full scan so an ambiguous handwritten matcher fails before policy or value
  consumption.
- P1: keep-last replacement needed explicit ownership semantics. The field hook receives `Replacing = True` and
  must preserve rollback safety. Ownership-counted tests prove one old-candidate release, one new acquisition, commit
  transfer, and exactly-once rollback cleanup after parse or final-validation failure.
- P1: field-by-field success did not establish record validity. `Finish_Candidate` runs after `End_Record` and all
  missing hooks, before the root transaction can publish the candidate.
- P1: defaults and overlay policy could not be allowed to rewrite structural facts. The missing hook contract
  forbids altering Known facts, replacing mandatory Unknown or Unsupported facts, or granting visibility;
  `Applied = False` performs no field mutation.
- P2: error-name documentation overstated retention. It now states the bounded prefix and `Name_Truncated` contract.
- P2: representative metadata failures now cover field and alias counts, name length, invalid UTF-8, duplicate
  primaries, cross-field aliases, and matcher no-match before an output event. Decode-side rejection proves cursor
  offset zero and candidate rollback.

## Accepted contracts

- Serialization emits every ordinal in declaration order. The runtime combinator does not infer conditional
  omission.
- Decode order is begin record, repeated full name resolution and exactly one child action, end record, missing
  hooks in ordinal order, then final candidate validation.
- Runtime ambiguity is `Application_Error` and wins over duplicate handling. Reject and decode errors retain the
  incoming name path; missing errors use the canonical primary name, subject to bounded path truncation.
- Unknown-ignore and keep-first each call `Skip_Value` exactly once. Keep-last calls the field hook exactly once.
- Local ordinals and presentation aliases are serde generator/overlay artifacts. They are not Type IR identities,
  wire tags, or a reason for either runtime to depend on the shared offline tooling.
- This generic covers records with one or more flattened logical fields. Null records and exact generated variant
  selection use separate adapters.

## Verification

- A forced full warning-visible library and assertion-enabled test rebuild completed successfully.
- The complete test binary ran successfully with JSON and CBOR record serialization/deserialization fixtures.
- Tests cover source-order independence, aliases, missing defaults, unknown and duplicate policies, ambiguity
  precedence, incoming and canonical paths, exactly-once skip/decode actions, replacement ownership, final validity,
  metadata bounds, invalid metadata before output/input consumption, rollback, and retained publication.
- `git diff --check`, the 110-column Ada scan, and the complete APM policy audit passed.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
