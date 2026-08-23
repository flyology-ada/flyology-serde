# Type IR boundary correction review — 2026-08-23

Scope: serde claims about the current `flyology_type_ir` extractor, v1 generic-actual coverage, and physical
representation provenance.

## Findings resolved

- P1: the serde docs described the planned Libadalang extraction surface as implemented. They now state that the
  current executable deliberately fails closed and emits no IR, and that existing fixtures prove schema/model shape
  plus GNAT legality rather than complete extraction acceptance.
- P1: generic association prose exceeded the v1 fixture matrix. It now limits current identity coverage to named
  unconstrained type actuals and exact scalar or text value/object facts, records the rejected constrained-type and
  expression-valued cases, and marks all other forms as not yet fixture-proven.
- P1: physical representation was described as ignored provenance. The docs now state that it may be located for
  extraction diagnostics but is not serialized in Type IR v1.
- P1: one residual sentence still treated current fixtures as accepted Libadalang-property coverage. It now states
  that each supported property combination needs a future dedicated extractor fixture before strict output.

## Boundary disposition

The correction changes no serde runtime or overlay authority. Type IR remains the prospective offline structural
boundary; serde generation must wait for a reviewed, published extractor/IR consumer subset and must fail closed on
unsupported or imprecise mandatory facts.
