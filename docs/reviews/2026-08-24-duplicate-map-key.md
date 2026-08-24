# Duplicate map-key status review

Status: accepted after proposal, implementation, and narrow fix re-review.

## Decision

`Duplicate_Key` distinguishes a rejected repeated logical map key from a duplicated record or variant field name.
The map entry callback still owns equality and replacement policy; the backend preserves source-order key/value
pairs and does not collapse them. A callback reports `Duplicate_Key` only when it rejects a decoded key as equal to
an earlier key. Accepted or replacement duplicates do not report it.

## Proposal review

Independent review reported P0 none and P1 none. It preferred the precise status over `Invalid_Value` and required
the duplicate-entry test to retain the zero-based map index path. Its P2 compatibility finding is accepted: adding
an `Error_Code` literal requires exhaustive client cases to migrate, and semantic adjacency changes later default
positions. The experimental crate promises neither positions nor a stable error ABI, so no representation clause is
added.

## Implementation review

The implementation review reported P0 none, P1 none, and no code or semantic P2. The initial final-review record was
the only remaining P2 and is closed here. A subsequent JSON parity test initially used object syntax, was corrected
to the backend's documented array-of-pairs map representation, and now proves the same duplicate status, exact index
path, publication preservation, and rollback as CBOR. Narrow re-review reported P0 none, P1 none, and P2 none. The
assertion-enabled suite, 110-column Ada scan, and `git diff --check` pass.
