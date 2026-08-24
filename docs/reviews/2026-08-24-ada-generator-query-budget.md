# Ada generator query-budget review

Date: 2026-08-24

Scope: the retained generation-request path and checked-overlay observation APIs. This change does not add Type IR
authority, lowering, artifacts, publication, or a successful generator CLI path.

Architecture review found two P1 gaps. Checked overlays returned allocating unconstrained strings and uncharged
semantic values, while generation copied its retained overlay path outside accessor accounting. The first proposal
also combined a count-reading indexed precondition with strict prelatched no-op behavior, which would have observed
the owner outside the budget before the query body.

The accepted contract removes every production request-path and overlay-text string getter. Scalar, count, and
length procedures charge one work unit and assign their `in out` result only after success. Copy procedures charge
one capacity probe and then the exact copied length, preserve every actual on denial, and distinguish an undersized
buffer through `No_Error` plus `Copied = False`. Checked overlay v1 text is printable ASCII; request paths remain
opaque non-NUL pathname octets. Indexed operations have only the valid-owner precondition. After diagnostic and
poison precedence, an invalid positive index is an uncharged programming error reported as `Internal_Error`.
Integer indices carry no cross-owner provenance.

The first implementation review found P0 none and P1 none. Five P2 findings required clarification of immutable
component selection under a latched diagnostic, direct request-path failure tests, parity coverage for every overlay
query wrapper, a generic rather than legacy-name API gate, and completion of this review record.

The fixes define latched calls by their externally observable effects: they perform no budget, diagnostic, or result
mutation, although a wrapper may select a retained immutable component before entering its common helper. Tests now
cover every nonindexed and indexed overlay text family, all scalar and count families, exact request work, output
path mapping, undersize, probe and byte denial, non-one-based output, invalid-index precedence, clean and poisoned
prelatched calls, opaque path bytes, and preservation of every result actual. Decode-only maxima are captured before
any query. The smoke suite parses complete Ada declarations and rejects any function returning `String` in either
production query specification.

Final independent fix review: P0 none, P1 none, P2 none. The nested generator build and test project, smoke suite,
runtime build and tests, Python generator tests, generated JSON/CBOR fixture tests, release-marker scan, golden
manifest verification, APM audit, `git diff --check`, and the explicit 110-column Ada scan pass. GNATformat is not
available in the installed toolchain; compiler style checking remains enabled and passes.
