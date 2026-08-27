# Type IR ledger bridge proposal

Status: accepted and implemented after architecture, change, narrow fix, and final whole-diff review.

## Problem

The offline Ada generator must pass its one operation budget through the reviewed
`Flyology_Type_IR.Operation_Budgets.Ledger` interface.  Type IR's cost model uses positive
`Interfaces.Unsigned_64` charges and requires a denied reservation to debit nothing and change no ledger state.
The existing `Requests.Operation_Budget` entry points accept `Natural` and deliberately poison the budget when a
charge is denied.  An adapter cannot split a Type IR charge into smaller calls because the Type IR contract requires
one atomic reservation, and it cannot call the current entry points because a denial would violate the ledger
provider contract.

## Proposed boundary

Add the following dependency-neutral reservation seam in a new private child,
`Flyology_Serde_Generator.Requests.Atomic_Ledgers`:

```ada
type Category is (Input_Bytes, Work_Units);
subtype Charge_Amount is Interfaces.Unsigned_64 range 1 .. Interfaces.Unsigned_64'Last;
type Reserve_Result is (Reserved, Denied, Bridge_Failed);

procedure Try_Reserve
  (Value    : in out Operation_Budget;
   Kind     : Category;
   Amount   : Charge_Amount;
   Result   : out Reserve_Result);
```

The child declaration, category, amount, result, and operation are private to the generator implementation.  They
do not expand the visible `Requests` API or let an ordinary overlay/rendering caller bypass poison-on-denial
semantics.

`Try_Reserve` is nonraising for ordinary synchronous calls.  It starts with `Result := Bridge_Failed`.  An already
poisoned budget or inconsistent private state is an unchanged `Bridge_Failed`, not a capacity denial.  Inconsistent
state includes a selected current count above its retained ceiling.  If the complete amount fits the selected
remaining ceiling, it is debited exactly once and the result becomes `Reserved`.  Ordinary insufficient capacity,
an amount above `Budget_Count'Last`, or an amount above the selected residual returns `Denied`; every usage counter,
limit, and poison bit remains unchanged.  The check proves `Current <= Maximum`, converts only after proving that
`Amount <= Budget_Count'Last`, computes the selected post-count locally using subtraction before addition, performs
one selected-counter assignment as the final state effect, and then publishes `Reserved`.  No later fallible work
occurs.  Task abort propagates; if delivery occurs after the one complete debit, that debit is retained and never
refunded.

The existing `Charge_Input` and `Charge_Work` operations keep their current poison-on-denial behavior for
consumer-owned overlay, rendering, and request operations.  Their behavior is not silently changed.

When the reviewed Type IR dependency is available, a minimally visible nonprivate child,
`Flyology_Serde_Generator.Requests.Type_IR_Ledgers`, will be the only unit that imports both APIs.  It owns one
private limited adapter with a not-null access discriminant designating the exact aliased `Operation_Budget`
retained by `Generation.Generate`.  Its visible surface is only a scoped `With_Operation` facade, bridge result
status, and the Type IR operation callback needed by that facade; no constructor or adapter object is exposed.
The private adapter derives from `Flyology_Type_IR.Operation_Budgets.Ledger`, returns exactly
`Cost_Model_V1` from `Supported_Cost_Model`, forwards one Type IR charge to one `Try_Reserve` call without
split/retry/reorder/refund, and retains a private bridge-failed latch.  `Reserved` maps to `Granted=True`; `Denied`
maps to `Granted=False`; `Bridge_Failed` latches failure and also returns `Granted=False` so no exception crosses the
provider call.  That latch is sticky for the rest of the scoped operation: every unexpected later provider call
returns `Granted=False` without another reservation or `Operation_Budget` mutation.  It is out-of-band bridge
failure evidence, not a capacity-denial debit or `Operation_Budget` accounting-state change.  After the Type IR
operation returns, the facade checks the adapter latch before returning its bridge result to `Generation`, so an
internal bridge failure becomes `Internal_Error`, never ordinary exhaustion.

The adapter and its access exist only in the dynamic scope surrounding one
`Flyology_Type_IR.Operation_Budgets.With_Operation` call.  The operation session and every checked-owner query use
that same adapter/session.  Neither Serde nor Type IR retains the adapter or budget reference after the call, and
the generator does not recursively enter the adapter.  `Generate` checks the existing diagnostic and budget poison
state before invoking the facade; a prelatched diagnostic or poisoned budget performs no Type IR call, charge, or
diagnostic replacement.  Only a `Denied` result from an initially clean active budget maps the Type IR result to
`Resource_Exhausted`, followed by exactly one explicit poison.  A provider violation, bridge-failed latch, or
unexpected exception maps to `Internal_Error` and poison while preserving an earlier primary diagnostic.

This first implementation change adds and tests only `Requests.Atomic_Ledgers`; it does not add the unpublished
Type IR dependency, construct a checked owner, lower a model, render output, or make persisted JSON production
authority.  The nonprivate bridge facade with its private adapter and adapter-level tests lands with the reviewed
Type IR pin.

One `Operation_Budget` remains the aggregate ledger for overlay loading, Type IR extraction/query, lowering,
rendering, and publication.  The adapter must not create a second budget, reset the existing budget, split or
reorder one Type IR reservation, or refund an accepted charge.  Type IR's cost-model version remains explicit at
the adapter call; this seam does not infer or store that version.

## Evidence required before commit

- exact-bound success and one-over denial for both categories;
- on a fresh maximum-ceiling budget, successful reservation of exactly
  `Interfaces.Unsigned_64 (Budget_Count'Last)`, for both categories;
- on a fresh maximum-ceiling budget, unchanged denials for amounts formed explicitly in the unsigned domain as
  `Interfaces.Unsigned_64 (Budget_Count'Last) + 1` and `Interfaces.Unsigned_64'Last`, for both categories;
- with ceiling `Budget_Count'Last` and current `Budget_Count'Last - 1`, acceptance of one followed by unchanged
  denial of another one, for both categories;
- with ceiling `Budget_Count'Last` and current `Budget_Count'Last - 2`, unchanged denial of three followed by
  successful reservation of two, for both categories, proving subtraction-based residual accounting and reuse;
- already-poisoned and deliberately inconsistent private-state calls are unchanged `Bridge_Failed` results;
- input and work counters remain independent;
- every denial/failure test snapshots all five usage counters, all sixteen limits, and poison state before and after;
- an output initialized to a different result proves `Result` is assigned on every normal path;
- direct traces prove one call produces at most one debit and no ordinary exception escapes;
- the visible `Requests` specification remains byte-for-byte unchanged, while a non-descendant compile probe that
  attempts to `with Requests.Atomic_Ledgers` fails specifically because it is a private child;
- forced warning-visible generator build, scaffold tests, smoke suite, root/runtime tests, Python differential
  generator tests, generated JSON/CBOR fixture tests, dependency gates, APM 0.28.0 audit, and final diff/style checks;
- independent change and final reviews report P0/P1/P2, with every finding closed before commit.

The later adapter milestone additionally requires direct tests for a prelatched diagnostic, prepoisoned budget,
first Type IR denial followed by exactly one explicit poison, preservation of accepted earlier charges, provider
exception/bridge failure to `Internal_Error`, both category mappings, exact cost-model identity, and the absence of
split, retry, reorder, or refund.  A second provider call after a latched bridge failure must perform no reservation
and retain the same failure.

## Review record

Two independent architecture reviewers initially reported P0 none, three P1 findings, and five P2 findings.  The
accepted correction keeps the atomic primitive in a private child, distinguishes unchanged denial from internal
bridge failure, gates prepoisoned operations, defines a nonprivate facade with a private limited adapter for the
later Type IR pin, fixes its Ada lifetime and callback contract, and closes every arithmetic and visibility test
edge.  Both final proposal reviewers then reported P0 none, P1 none, and P2 none.

The independent implementation reviews reported P0 none and P1 none.  Their P2 findings added the explicit
signed-maximum fill-then-deny trace for both categories, exercised both prepoisoned categories, aligned the
result-initialization claim with the test, and updated the implementation status.  Both narrow fix re-reviews then
reported P0 none, P1 none, and P2 none.

Two independent final whole-diff reviewers inspected every tracked and untracked milestone path and reported P0
none, P1 none, and P2 none.  Both authorized the focused change for commit.

## Verification

- forced assertion-enabled generator test build, focused atomic-ledger test, and private-child negative compile;
- complete Ada generator build and smoke suite, including the source-list closure and O0/O2 hook-elision scans;
- root runtime build and assertion-enabled test crate;
- isolated static recursive install, public external-client JSON/CBOR execution, and private-oracle rejection;
- all 12 transitional Python generator tests and the generated fixture JSON/CBOR project;
- release-marker and fixture-manifest verification;
- both reviewed Flyology JSON dependency locks and all 10 dependency-checker tests;
- APM 0.28.0 cache-only audit with all 10 checks passing;
- pinned GNATformat over every new Ada source, `git diff --check`, and the 110-column scan.
