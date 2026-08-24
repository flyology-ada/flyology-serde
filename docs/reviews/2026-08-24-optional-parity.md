# Optional adapter parity review

Status: accepted.

## Scope

This test-only tranche exercises the generic optional adapter through
application-owned root candidates. It changes no runtime capability, backend
representation, Type IR fact, or wire behavior.

The same typed roots distinguish none from some(integer), outer none from
some(inner none), and none from some(null) through JSON and CBOR. Exact envelope
bytes are asserted alongside published semantic state. Null construction is an
explicit callback and occurs once only for some(null).

Post-consumption status and exception injection prove root abort and rollback
while an optional scope is open. A failing Set_Absent callback proves the other
construction branch. A direct prelatched call proves the optional combinator
itself leaves both candidate and reader untouched before same-reader success.

## Proposal review

Independent proposal review reported P0 none and P1 none. Its P2
requirements—same typed
distinction roots, both formats for semantic cases, explicit null construction
counts, post-consumption failures, Set_Absent failure, direct prelatched
same-reader proof, and repeatable serialization callbacks—are incorporated.

The implementation review reported P0 none, P1 none, and three P2 test-strength
findings. Successful roots now assert exactly one commit and no rollback. The
exception test matches the injected message exactly, proves that use without a
reset returns `Invalid_State`, and then proves reset and reuse. The narrow fix
review reported P0 none, P1 none, and P2 none.

## Verification

- `alr -C tests run`
- 110-column scan of changed Ada and review files
- `git diff --check`

`gnatformat` was invoked through the owning `tests.gpr`, but the configured
toolchain does not provide that executable. The compiler's configured style
checks and the explicit line-length scan are the formatting fallback.
