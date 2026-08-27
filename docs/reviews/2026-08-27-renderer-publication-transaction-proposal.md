# Renderer publication transaction proposal

Status: implemented checkpoint pending final change review. This document
changes no public API, generated source, budget formula, existing diagnostic
mapping, or artifact format. It adds one `Internal_Error` case for observable
cleanup damage after an otherwise complete in-memory replacement.

## Problem

`Flyology_Serde_Generator.Rendering.Render_Payload` currently keeps an
unpublished allocation in a raw access variable and publishes it with three
unguarded pointer statements. Task abort is not required to run the procedure's
exception handlers. Abort can therefore leak the unpublished allocation or
interrupt replacement after one owner has changed but before the other has
become inert.

This is a pre-existing correctness defect. It must be fixed before another
generator input mode reuses the renderer.

## Ownership states

The implementation uses a private limited controlled holder whose only
state is either empty or sole ownership of one unpublished `Artifact_Data`.
Its nonraising finalization detaches and discards exactly that allocation. A
raw access value is never the durable owner across an abort-completion point.

Candidate allocation is a small abort-deferred transaction:

1. start with a private `Defer_Active := False` latch;
2. call `Abort_Defer`, then set the latch True only after that call returns;
3. allocate and place the returned access value directly in the already-live
   holder;
4. set the latch False immediately before the one `Abort_Undefer` call.

The region's handler tests the latch. If it is still True, the handler first
sets it False and then calls `Abort_Undefer` exactly once before propagating to
`Render_Payload`'s existing diagnostic-mapping handler. An exception from, or
task abort delivered by, `Abort_Undefer` is never followed by another
`Abort_Undefer`. A pending task abort delivered by `Abort_Undefer` can supersede
an ordinary exception under Ada tasking semantics; “primary preservation” below
therefore applies to cleanup exceptions, not to a subsequently delivered abort.

Allocation failure leaves the holder empty. A pending abort is delivered only
after the holder owns the allocation, so controlled unwinding can discard it.
Rendering then writes only through the holder-owned candidate. Every ordinary
render failure and every abort before publication leaves the existing
`Rendered_Artifacts` value unchanged. Budget charges remain consumed.

## Publication

Publication uses two already-live controlled holders after both generated
payloads have passed all existing structural and length checks. The candidate
holder owns the new artifact and an empty previous holder is ready to receive
the old artifact. The abort-deferred portion is only an elementary ownership
transfer:

1. defer abort;
2. move the previous allocation from `Into` into the previous holder;
3. move the holder's complete candidate into `Into` and make the holder empty;
4. set the region's private active latch False and undefer abort exactly once;
5. leave the nested previous-holder scope, causing automatic controlled
   finalization to make exactly one nonraising cleanup attempt.

Publication uses the same latch algorithm as allocation: the latch becomes
True only after `Abort_Defer` returns, becomes False immediately before every
`Abort_Undefer`, and a handler undefer is permitted only while the latch is
True. There is no retry or second undefer when undefer itself transfers control.

There is no callback, deallocation, allocation, budget operation, rendering
operation, or other user-controlled work in this deferred publication region.
No call or hook occurs between the first pointer move and `Abort_Undefer`.
The pointer moves occur only while abort is deferred. If a pending abort is
delivered by undefer, controlled unwinding makes the previous holder's one
cleanup attempt. Otherwise normal scope exit makes that attempt after undefer.
Consequently, when `Render_Payload` returns or an abort is delivered, `Into`
owns exactly one of these states:

- its complete prior artifact, if publication did not start; or
- the complete newly rendered artifact, if the publication transfer finished.

It never owns a partially rendered artifact, and the holder and `Into` never
own the same allocation after abort becomes deliverable. A pending abort in the
publication region is delivered after the complete new artifact has replaced
the old one. The caller must not interpret task completion as a successful
generation result. Finalization of `Into` retains the nonraising
exactly-one-attempt cleanup guarantee defined below; it does not claim leak
freedom if the underlying deallocator violates the supported boundary.

An unexpected ordinary exception in either abort-deferred region re-enables
abort before propagation to `Render_Payload`'s outer diagnostic-mapping
handler. Cleanup remains nonraising and cannot replace that exception. A task
abort delivered by the required undefer may supersede it, as described above.
Existing expected-error translation and budget-poison rules remain unchanged.

The previous holder is declared in a nested block and receives access to an
outer cleanup-result scalar. Its `Finalize` reports whether its exactly one
deallocation attempt returned normally. Product code never calls that
`Finalize` explicitly. Ada automatically defers abort while finalizing a
controlled object, so the finalizer may detach the access value and enter
`Free` without exposing a raw unowned pointer at an abort-delivery point. It
contains every cleanup exception and writes the result before returning.
Allocator/component cleanup may acquire implementation locks; that work is
deliberately outside the elementary publication region but inside the
language-defined abort-deferred finalization. The supported GNAT/Ada
standard-library boundary assumes finalization of the four
`Unbounded_String` components and their unchecked deallocation do not raise.
The maintained successful-free evidence is valid only under that boundary. If
standard-library finalization or deallocation nevertheless raises, the pointer
has already been detached and cannot safely be retried: the cleanup is damaged
and storage may be lost, although no second owner or second free is created.
The implementation and documentation must therefore claim exactly one cleanup
attempt and no double free, not unconditional leak freedom under a failing
deallocator. On normal scope exit, a failed cleanup result poisons the operation
budget and sets `Internal_Error` when the diagnostic is still clear. The
complete new artifact remains owned by `Into`, but a caller must not publish it
after that failure; subsequent use of the poisoned budget remains fail-closed.
If another diagnostic is already primary, cleanup damage cannot replace it. A
cleanup attempt reached through task-abort unwinding remains nonraising and the
pending abort prevents subsequent diagnostic publication.

## Test seam

A private test-hook package exposes deterministic pause points immediately
after holder ownership is established, immediately before publication, and
inside the abort-deferred publication region before the first pointer move. It
also identifies every allocation and successful free by a nonreused test
identity. The enabled hook registry keys that identity by the allocation's
opaque address while the allocation is live; it never dereferences a retained
address. Before `Free`, one protected transition removes the address and marks
the nonreused identity releasing. After `Free`, success or damage is recorded
by identity, so concurrent address reuse cannot clear another generation.
Production `Artifact_Data` contains no test identity or test-only layout. A
finalization pause
immediately after pointer detachment but before `Free` proves that a pending
abort remains deferred until the one cleanup attempt completes. Counters are
protected, nonraising, saturating, and used only for evidence; overflow fails
the test.
Reset/disarm is explicit, one-shot, and permitted only after every worker task
has terminated. A release is recorded only after `Free` returns normally, not
merely after the pointer is detached. The enabled package exists only in the
generator test project. The production project sees a disabled specification
with a literal `Enabled : constant Boolean := False` and imported-only
sentinels.

Every executable hook reference, including helper-body references, remains
inside a literal `if Test_Hooks.Enabled` branch. The production ALI and debug
strings may name the disabled specification and its types because the body
withs that private unit; they are not executable dependencies or state.
Maintained `-O0` and optimized source/layout, ALI-sentinel, object-symbol, and
object-string scans prove that production objects retain no test state,
callable hook, or imported-only sentinel. No hook or other call may occur
between the first publication pointer move and `Abort_Undefer`. The statement
above that publication contains no callback or blocking work applies to the
production body after this static hook elision; the enabled test build
intentionally pauses before the first move.

Every test pause and controller wait is bounded. The pause has a nonraising
release/cancel path that a controlled test guard invokes on controller
exception, assertion failure, timeout, or abort. A failed controller therefore
cannot strand a worker inside an abort-deferred region. Timeout is a test
failure and the worker is joined after release before any shared-state check.

Deterministic task tests prove:

- abort after candidate ownership and before publication releases the candidate
  once and preserves a pre-existing artifact;
- abort immediately before publication preserves the pre-existing artifact;
- abort requested inside the deferred publication region is delivered only
  after the complete replacement, releases the old artifact once, and leaves
  the new artifact solely owned by `Into`;
- ordinary exceptions injected after holder attachment and before the first
  publication move, both with and without a pending abort, exercise every
  latch/handler path without a double undefer;
- abort immediately before previous-holder finalization and after its internal
  detach but before `Free` still produces exactly one cleanup attempt;
- injected cleanup-pause timeout and exception outcomes still perform the one
  `Free` attempt, correlate its identity, retain the complete replacement, and
  report cleanup damage;
- a test-only one-shot cleanup-damage result injected only after a real
  successful free exercises budget poisoning, `Internal_Error` for a clear
  diagnostic, preservation of an existing primary, retention of the complete
  new artifact, and the result that a caller's publication gate must reject;
  the hook is evidence for result handling, not a test of a separate caller or
  a claim that the deallocator failed;
- ordinary render failure preserves a pre-existing artifact;
- successful replacement releases the old artifact once and later finalization
  releases the new artifact once; and
- repeated replacements plus aborts at each ownership phase produce the
  expected one-attempt cleanup identities and no double free under the
  supported nonraising deallocator boundary.

The tests use an in-place limited `Rendered_Artifacts` shared by the test owner;
they do not rely on copy-out from an aborted task. The owner joins or otherwise
observes terminal task completion before reading the shared object or resetting
hooks. Assertions compare the exact prior and replacement file names, lengths,
and payload bytes, retain each worker budget for post-termination accounting,
and correlate each old/candidate/new allocation identity with its exact
successful free. Aggregate counts alone are insufficient. Hooks never enter
installed or generated runtime code.

## Boundaries

This transaction owns only the two in-memory generated Ada artifacts. It does
not publish files, attest a generator build, authorize Type IR or Reflection,
or change Serde runtime traversal. Filesystem staging/publication remains a
separate fail-closed generator stage. No Wire, Type IR, Reflection, or JSON
dependency follows from this fix.

## Freeze gates

Before commit:

1. independent architecture review reports P0/P1/P2 none;
2. the implementation and deterministic abort tests pass under the generator
   test project;
3. production hook-elision scans pass at every maintained optimization level;
4. the complete generator, root, and APM gates pass; and
5. independent change and final diff reviews report P0/P1/P2 none.
