# Core implementation review — 2026-08-23

Scope: optional events, backend capability reporting, bounded decode budgets, and counting-protocol validation.

## Findings resolved

- P1: a declared container length was bounded, but an unknown-length container could exceed the item limit while it
  was consumed. `Decode_Budget` now keeps a bounded per-depth item count and charges every accepted item.
- P1: a runtime-selected nesting limit could exceed fixed budget storage. `Nesting_Limit` now makes the maximum
  supported depth part of the public policy type.
- P2: optionality existed only in design prose. It now has a distinct logical kind and balanced zero-or-one-child
  serializer/deserializer grammar, and the counting backend validates its cardinality.
- P2: adapters could discover unsupported format behavior only after emitting. Backends now report stable
  capabilities for unknown lengths, bytes, nonfinite binary64, signed zero, arbitrary map keys, and lossless
  optionals; an adapter checks required capabilities before emitting or mutating.
- P2: counter and budget arithmetic could otherwise rely on implicit range checks. Both paths check capacity before
  addition and return status errors.

## Boundary review

Optional events and format capabilities are serde runtime concepts, not Type IR structural facts or wire runtime
interfaces. Type IR records Ada default and bound structure; the serde overlay may consume but never alter Known
facts, replace mandatory Unknown/Unsupported facts, or grant visibility.

## Verification

- `gnatformat` completed for all changed Ada sources.
- `alr build` passed.
- `alr -C tests run` passed with assertions enabled.
- The final staged diff must remain clean before commit.

## Post-publication wire review fixes

- P1: `Nested_Optionals` did not state whether `some(null)` and every nested presence combination remain distinct. It
  is replaced by the normative `Lossless_Optionals` guarantee.
- P1: a latched error prevented budget scope cleanup. `Leave_Container` now unwinds valid entered scopes while
  preserving the primary error, and a nested failure/unwind/reuse regression test covers the lifecycle.
- P1: charging ownership was ambiguous. One concrete deserializer owns the budget and charges input, values,
  container items, and copied lengths exactly once; generated adapters bound only schema/candidate work.
- P2: capabilities are stable per operation and required capability failure precedes output or destination mutation.
- P2: JSON and CBOR input budgets and offsets are bytes; another backend must declare and retain its unit.
