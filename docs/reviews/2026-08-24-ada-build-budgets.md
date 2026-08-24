# Ada build verifier budget review

## Scope

The future bootstrap verifier must bound aggregate external bytes and aggregate work independently of individual
file, tree, and child-process structural limits. This change adds an offline-generator-private, single-owner ledger
with exactly `Input_Bytes` and `Work_Units` categories. It does not choose repository action ceilings, add command-line
options, run a child process, mint a generator identity, or affect the serde runtime.

The ledger has no implicit defaults: a default object is failed with zero usage, and `Initialize` is the only reset.
One positive U64 reservation is all-or-nothing. Denial debits nothing, preserves all prior usage, and globally latches
exhaustion so later categories cannot proceed. `Poison` changes an active budget to failed but preserves a prior
exhaustion status. The private child is accessible only to descendants of the noninstalled generator parent, so its
internal U64 subtype and state names are not a public consumer contract.

## Review cycles

The proposal review reported P0 none. It initially rejected a public positive-U64 interface decision without user
authority and requested a U64 charge type, explicit default state, single-owner wording, minimal queries,
subtraction-based overflow guards, and cross-category tests. The implementation moved the ledger to a private child,
made charge and limit values the same exact U64 subtype, defined the failed zero default, and incorporated all of the
requested semantics. The narrow proposal re-review reported P0 none, P1 none, and P2 none.

The independent implementation review reported P0 none and P1 none. Its one practical P2 found that exact-full and
one-over tests did not distinguish an atomic denial from a partial debit when capacity remained. The added trace
grants 1 of 3 input bytes and 2 of 5 work units, denies a request for 3 input bytes, proves usage remains exactly 1/2,
then proves the sticky cross-category denial also preserves both counters. The narrow fix re-review reports P0 none,
P1 none, and P2 none.

## Verification

- Default failure, active poison, exhaustion-preserving poison, and initialization from every terminal state pass.
- Exact U64-last input and work reservations pass without modular wrap; the next reservation rejects without debit.
- Exact small limits, partial-capacity denial, sticky cross-category rejection, and usage preservation pass.
- A forced warning-enabled GNAT 16 build, the focused budget executable, and the complete generator smoke suite pass.
- `git diff --check` and the explicit 110-column scan pass. `gnatformat` was invoked through the owning test project,
  but the selected host and Alire toolchains do not provide it; compiler style checks remain enabled and pass.

Exact file/process/parser charge events and their ordering remain part of the later consumer slices. This ledger alone
is neither an action policy nor build-identity authority.
