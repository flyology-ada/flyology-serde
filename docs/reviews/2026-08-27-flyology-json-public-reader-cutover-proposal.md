# Flyology JSON public reader cutover proposal

Date: 2026-08-27

Status: accepted and implemented. Independent architecture, implementation,
and corrective reviews report P0/P1/P2 none. The evidence below passed before
the cutover was committed.

## Goal and boundary

Make the reviewed Flyology JSON event-backed engine authoritative for
`Flyology_Serde.Deserializers.JSON.Reader` without changing the public reader,
adapter, policy, error, budget, JSON representation, CBOR, writer, generator,
Type IR, or Wire contracts. The strict `No_Extensions`, RFC 8259,
Unicode-scalar, BOM-rejecting, `Preserve_Unchecked` parser profile remains
fixed and private. No parser, event, range, retained window, fragment, profile,
or raw source access becomes a public Serde type.

## Package shape

Rename the completed private child implementation to the private sibling
`Flyology_Serde.Deserializers.JSON_Event_Readers`. The sibling owns every
Flyology JSON parser and event dependency. The public JSON specification may
then depend on it only in the private context and retain one limited
`JSON_Event_Readers.Reader (Source)` component as the complete private full
view of the public reader.

The public body is a nonallocating delegation layer. Every typed traversal,
finish, abort, capability, completion, and offset operation invokes the exact
event-reader operation once. `Initialize` and `Reset` retain their existing
signatures without an error parameter. Each uses a clean local diagnostic.
The private event reader adds one wrapper-only `Reinitialize` operation. Public
`Initialize` may use it from `Uninitialized`, `Ready`, `Active`, or `Complete`;
from `Failed` it retains the failed latch, so the documented recovery path is
`Reset` only. Public `Reset` may use it from every state. Each public operation
delegates once. The seam abandons any permitted prior parser operation through
the driver's existing initialize-or-reset path and establishes one fresh
reader operation; it does not inherit the stricter direct event-reader
`Initialize` rule for nonfailed reuse.

An ordinary diagnostic failure returns normally, retains only the event
reader's failed latch, and intentionally discards the local diagnostic; the
next error-bearing public operation reports the established `Invalid_State`
behavior. An exception from event initialization or reset propagates only
after the event reader has poisoned and cleaned its operation. The wrapper
does not catch, abort again, translate, or suppress that exception. Neither
path silently publishes a traversable reader.

`JSON.Copied_Input`, root adapters, derived readers, and generated code keep
constructing the same public discriminated type. They neither know nor depend
on the sibling implementation type.

## Temporary handwritten oracle

Move the current handwritten body and its exact private representation,
without semantic repair, into the test-project-only private sibling
`Flyology_Serde.Deserializers.JSON_Handwritten_Oracle`. No oracle source lives
under the production `src/` directory or enters the production build, archive,
installed specifications, objects, or ALIs. It remains temporarily compiled
only by the test project to preserve a second semantic scanner/state machine
during the focused cutover. It exposes bounded scalar query copies for input,
value, logical-depth, budget-depth, cursor, and completion observations; tests
never inspect its private record or retain internal access values.

The handwritten oracle is not independent of all JSON machinery: like the
event-backed reader, it uses `JSON_Event_Drivers` for parser admission, source
offsets, and raw-input budgeting. Differential parity is evidence for semantic
lowering and state-machine behavior only. Shared-driver, parser-profile,
Unicode, source-offset, and admission faults remain covered by frozen expected
transcripts/results plus the direct Flyology_JSON and driver conformance gates;
oracle agreement alone cannot close those claims.

The event-reader test matrix changes its `Oracle` objects to this private type.
The public JSON tests, adapter tests, allocating tests, generated fixture, and
copied-input facade use only the public reader and therefore exercise the
event engine after cutover. A later focused subtraction change may delete the
handwritten package only after the public matrix is green and another review
finds no oracle-only behavior. This cutover does not authorize that deletion.

## Ownership and failure invariants

- The public reader and its implementation borrow the same immutable source
  for the same Ada accessibility lifetime.
- The public wrapper contains no second cursor, budget, stack, parser, or
  completion state and cannot split authority between engines.
- All caller outputs and the primary diagnostic are produced directly by one
  delegated operation; the wrapper performs no candidate publication.
- Abort and Reset reach the same implementation owner exactly once. Abnormal
  cleanup, parser abort, budget unwind, and retained-window disposal remain in
  the event engine.
- A prelatched diagnostic remains a strict traversal no-op. The existing
  ordinary hidden initialization diagnostic leaves the implementation failed;
  an abnormal `Initialize` or `Reinitialize` exception propagates only after
  poison and cleanup. Neither path publishes a traversable reader.
- Public query helpers observe copied scalars only. No wrapper query advances,
  charges, resets, or repairs the implementation.

## Required evidence

Before committing the cutover:

1. Compile every public direct reader, adapter, allocating, copied-input,
   generated-fixture, and derived-reader test against the wrapper.
2. Run the complete unmodified-input public-versus-handwritten differential
   matrix for every scalar, envelope, container, error, offset, output
   clearing, budget counter, arbitrary bound, abort, repeated `Initialize`,
   `Reset`, and root transaction. Separately run event-only transcript
   mutation and exception-injection tests; those prove event cleanup and state
   behavior, not differential parity.
3. Exercise every operation and query through the public-wrapper matrix,
   including default outputs, prelatched calls, ordinary diagnostic failure,
   injected exception traces for both `Initialize` and `Reset`, exact abort
   counts, failed queries/traversal, Reset recovery, and derived dispatch. A
   source gate fixes the closed delegation set and exact call count for each
   public operation; the wrapper itself gains no test hook or second state.
4. Prove that the public full view contains one implementation owner and no
   handwritten state, and that the temporary oracle is unreachable from the
   production Alire/GPR source closure or any emitted install payload.
5. Extend forbidden-dependency and symbol checks so production public objects
   contain the event implementation but no handwritten-oracle reference and
   no enabled test-hook or disabled sentinel. After a clean production build,
   scan the source closure, archive, objects, and ALIs for the oracle and
   obsolete child names. Compile one valid external client through the
   production project and prove that an otherwise identical client cannot
   `with` the test-only oracle.
6. Run root build/tests, Flyology JSON lock checks, O0/O2 hook elision, all Ada
   and Python generator gates, generated-fixture compilation, APM 0.28.0
   reproduction, formatting, line-length, shell-syntax, and diff checks.
7. Gate the changed file set and visible API surface: the visible part of the
   public JSON specification and all adapters, policies, errors, budgets, JSON
   representation, CBOR, writer, generator, Type IR, and Wire files remain
   byte-for-byte unchanged. The JSON specification's private context and full
   view necessarily change. Rebuild all dependents because the private
   `Reader` representation changes.

The architecture and change reviews must resolve every P0/P1 and normally P2
before the public engine freezes. The following handwritten deletion remains a
separate architecture/change/subtraction review.

## Review and evidence record

The initial architecture and implementation reviews reported P1/P2 findings
covering failed-reader recovery, the test-only oracle boundary, the split
between differential and direct evidence, public-wrapper coverage, exact
delegation, production/install isolation, visible-API gating, and historical
package naming. Later isolation reviews also found imprecise obsolete-basename
matching, incomplete independent staging of Flyology JSON, and an oracle
rejection check that an unrelated compile failure could satisfy. All findings
were corrected. The final architecture, implementation, and isolation
re-reviews each report P0/P1/P2 none.

The accepted implementation passed:

- the root Alire build and complete Ada test executable;
- both reviewed Flyology JSON lock checks and all public cutover source gates;
- O0/O2 enabled/disabled hook-elision, clean production-tree scanning, staged
  install scanning, and isolated external-client acceptance/rejection;
- the Ada generator build, scaffold compilation, smoke and lifecycle tests,
  generated-fixture conformance project, twelve Python generator tests,
  release-marker checks, and manifest verification;
- APM 0.28.0 frozen reproduction/audit, pinned GNATformat, shell syntax,
  110-column, and diff checks.

The handwritten oracle remains test-only and deliberately retained. Its
deletion is not part of this decision.
