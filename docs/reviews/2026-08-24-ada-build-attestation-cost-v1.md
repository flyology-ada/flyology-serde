# Ada build attestation cost model v1

Date: 2026-08-24

Status: accepted and implemented for the private request-owner foundation only. It selects no production limits
and authorizes no filesystem, Git, stage, build, or publication action.

## Common rules

All charges debit the caller's existing `Flyology_Serde_Generator.Build_Budgets` session. `Work_Units` is the
only category used by this foundation slice. Every reservation is positive, atomic, ordered as written, and never
refunded. Denial exhausts the ledger, reports the operation's `*_Budget_Exhausted` status, performs no later
reservation or effect, and preserves every caller-visible owner and output. A failed ledger reports
`*_Budget_Failed` without charging.

For every operation, a non-success input status is a zero-charge no-op. The remaining zero-charge gates occur in
this order: exact owner/session match, current budget state, then retained-state validity. Structural limit checks
that precede byte observation are also uncharged. A retained payload's stored session must match the active session
before any other payload field is observed; a stale payload reports the operation's `*_Session_Foreign` status
without charging. `Storage_Error` after a successful reservation reports the operation's allocation status,
poisons an active ledger, retains prior charges, and preserves the prior owner.
Unexpected exceptions report the internal status and poison an active ledger. Cleanup and finalization are
uncharged and cannot replace an earlier primary failure.

Every partial allocation is owned immediately by a local limited controlled candidate. The implementation defers
abort across each raw allocation-to-candidate transfer and each final candidate-to-retained-owner transfer. Abort
unwinds the unpublished candidate without translating the abort into a status, leaves the prior retained owner
unchanged, and leaks no allocation. No fallible operation follows the final pointer/link transfer inside the
abort-deferred region; delivery after the corresponding undefer observes ownership already attached to the caller's
limited owner.

## Closed lexical domains

A request path is a POSIX pathname-octet sequence represented by one Ada `String`. It contains no NUL, starts with
`/`, has no empty component, has no `.` or `..` component, and has no trailing `/` unless it is exactly `/`.
Repeated `/` is therefore invalid. Every non-NUL, non-`/` octet is otherwise retained exactly; the package performs
no Unicode, case, symlink, or host-normalization equivalence. A normalized child lies below a normalized root only
when the root is `/` and the child is longer than `/`, or when the child's exact prefix is the root followed by
`/`. Equality is not containment. This lexical test is preliminary input validation, not filesystem authority;
the future stage transaction must still use retained no-follow identities and reject namespace changes.

A canonical dependency name is nonempty ASCII matching `[a-z][a-z0-9_]*`. No case folding or punctuation alias is
accepted. The exact bytes are the active-lock and dependency-identity comparison key.

## Request operations

`Initialize` observes its five text inputs in formal order: `Generator_Root`, `Git_Executable`, `Toolchain_Root`,
`Staging_Parent`, then `Active_Lock`. For each text:

1. Reserve one `Work_Units` probe.
2. If the length is zero or exceeds `Maximum_Path_Bytes`, report `Request_Invalid` or
   `Request_Limit_Exceeded` respectively; do not reserve the byte amount.
3. Reserve exactly `Text'Length` `Work_Units` before lexical validation, retention, or allocation.
4. Scan and materialize under that reservation. Invalid absolute-path syntax reports `Request_Invalid` without
   refund.

The lexical component-boundary check that `Git_Executable` lies below `Toolchain_Root` is included in the already
reserved text-byte work and spends no additional charge. A nonempty existing request is rejected before text
observation and charging. Every path string and the completed payload follow the common controlled-candidate and
abort-deferred ownership rule. Publishing the completed request is a nonallocating, zero-charge pointer transfer.

`Add_Dependency` first checks the retained request is initialized and unsealed. Those rejections are
`Request_Invalid` and uncharged. A count already at `Maximum_Dependencies` is
`Request_Limit_Exceeded` and uncharged. It then observes `Crate` and `Active_Prefix` in that order. Each text spends
one probe, applies its named structural byte limit, then spends its exact nonzero length before lexical validation
or allocation. `Crate` uses `Maximum_Dependency_Name_Bytes`; `Active_Prefix` uses `Maximum_Path_Bytes`. Empty or
lexically invalid text reports `Request_Invalid` after its probe or byte charge as applicable.

After both texts validate, existing crate claims are compared in insertion order. Each comparison reserves one
`Work_Units` probe and then exactly `min (existing crate bytes, Crate'Length) + 1` `Work_Units`. A matching crate
reports `Request_Invalid` after that comparison; no later claim is inspected. Allocation and the abort-deferred
single-link publication spend no additional work. The new node and both retained strings follow the common local
controlled-candidate rule. Allocation failure or abort preserves the prior linked list.

`Seal` checks the request is initialized and unsealed, then reserves exactly one `Work_Units` before the
nonallocating sealed-state transition. Repeated sealing is `Request_Invalid` and uncharged.

## Explicitly unavailable operations

In this slice, a valid sealed `Create_Checked_Stage` returns `Stage_Attestation_Unavailable` after the common
zero-charge gates and retained-state checks. It performs no reservation or filesystem/process work and preserves
any prior stage. Because no stage can be created, `Read_Generator_Identity` returns `Query_No_Stage` and
`Publish_For_Build` returns `Publish_No_Stage`, both uncharged after their common gates.

The reviewed future identity query cost remains one `Work_Units` probe followed by exactly 64 `Work_Units` before
copy. It becomes reachable only in the separately reviewed stage-transaction implementation.
