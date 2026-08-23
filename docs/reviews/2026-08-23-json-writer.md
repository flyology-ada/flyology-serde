# JSON writer review — 2026-08-23

Scope: bounded and explicitly allocating JSON serializers and the logical-to-JSON representation.

## Findings resolved

- P1: the first bounded API returned an unconstrained `String`, which could use secondary-stack storage. Bounded
  output now uses caller-buffer `Copy_Output` and reports the required length; only the allocating writer returns an
  unconstrained convenience value.
- P1: an optional child was emitted without the comma after its presence tag. Nested some/none coverage now verifies
  the lossless `[1,[0]]` representation.
- P1: JSON objects cannot preserve arbitrary map key kinds. Maps use ordered arrays of key/value pairs and therefore
  correctly report `Arbitrary_Map_Keys`.
- P1: an output failure could leave a valid-looking prefix. A writer latches failure, never reports completion, and
  requires reset before reuse.
- P2: binary64 nonfinite handling and signed-zero capability were implicit. Nonfinite values fail before output;
  negative zero is covered by a sign-preservation assertion.
- P2: bytes, optionals, variants, and maps lacked a documented representation. `docs/json.md` fixes the mapping and
  states that representation tags are neither Type IR nor wire identity.

## Verification

- `gnatformat` completed for writer sources and tests.
- `alr build` passed without warnings.
- `alr -C tests run` passed for records, optionals, bytes, arbitrary-key maps, variants, escaping, signed zero,
  bounded capacity/reset, and allocating output.
- Final staged-diff review is required before commit.
