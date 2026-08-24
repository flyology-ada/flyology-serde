# Ada build process runner review

## Scope and ownership

The offline Ada generator needs a bounded child-process runner before it can attest exact Git dependency trees.
This change adds a private runner only. It does not invoke the runner from the executable, add a command-line
option, choose an action ceiling, mint a generator identity, load Type IR, or affect the serde runtime. The caller
supplies one complete `Process_Limits` value and one accessibility-bound `Build_Budgets.Budget`; commands, results,
and every observation remain bound to that budget's current nonreusing session.

A command contains one absolute executable, explicit arguments, and an explicit environment. The executable is
also `argv[0]`. Nothing is inherited from `PATH`, the environment, or standard input. Environment names are
nonempty and unique. The eventual Git caller must provide a single-process executable that creates no descendants
and does not change its process group, session, or credentials, plus a closed locale, configuration, and
object-database environment. This runner is the generator's only production spawn path. The group signal is defense
in depth for a violated single-process contract; the portable API does not claim to observe descendant quiescence
after a group kill.
The native leaf reports the header-dependent ignored-`SIGCHLD` and `SA_NOCLDWAIT` facts. Ada rejects either fact
before materializing the spawn request because both can autoreap the exact leader. The generator permits no
ambient handler to wait for runner-owned children; GNAT's nonreaping runtime disposition is compatible with that
ownership rule. The process contract excludes concurrent ambient disposition changes while the runner gate is
held; the fact query is not represented as atomic with `posix_spawn`.

The process-wide gate is acquired before the first raw `pipe`. It remains held while every raw descriptor is
replaced by a CLOEXEC duplicate and through the complete `Spawn_Exact` call, including immediate positive-PID
ownership publication. This prevents another runner call from opening a raw descriptor across the spawn. Every
unrelated descriptor in the generator must already be CLOEXEC. A successful PID is written directly into a limited
controlled guard before `posix_spawn` returns to Ada. The guard retains that unreaped identity until result capture
and mandatory cleanup are complete. Ordinary observation uses
`waitid(P_PID, ..., WEXITED | WNOHANG | WNOWAIT)`: it distinguishes no event from exact terminal exit or signal,
checks the returned PID, and never releases the PID/process-group pin. Cleanup closes every pipe once, sends one
group `SIGKILL`, then performs a blocking exact-leader `waitpid` with `EINTR` retry and validates any earlier terminal
observation against the final wait status. `ESRCH` is accepted only after another same-PID `WNOWAIT` observation
proves that the still-pinned leader is terminal; no event is a contract violation and fail-stops. Darwin can report
`EPERM` while the new group becomes zombie-only, so that case retains ownership and repeats the nonreaping same-PID
observation until terminal before the exact wait. A genuine inaccessible live leader therefore cannot return. An
`ECHILD`, unexpected wait result, or mismatched status poisons the process-wide runner and fail-stops. A pipe-close
failure is retained, child cleanup still finishes, and only then does the runner fail-stop. No normal or exceptional
path signals a process group after reaping its leader.

Raw pipe slots are controlled before `pipe`; all duplicated pipe ownership transfers to the child guard before
spawn. Gate acquisition, descriptor close, every descriptor move, command allocation and replacement, result
allocation and replacement, C-string materialization and release, and direct PID publication execute in paired
GNAT abort-deferred regions. No region enables abort until exactly one controlled owner remains. Explicit child
resolution occurs through controlled finalization so asynchronous abort is deferred across the cleanup transaction.
The private use of `System.Soft_Links` is intentionally GNAT-specific and is verified on every supported compiler;
it does not enter the runtime or generated API. An unexpected Ada/runtime exception in cleanup poisons before
either the test-only rethrow or the production fail-stop loop.

Command and result replacement are transactional. Every fallible validation, allocation, process operation, and
mandatory cleanup completes before a nonallocating pointer swap publishes a new value. Discard is nonraising and
clears ownership even if finalization fails; a discard defect can poison the operation but cannot replace its
primary status or roll back an already committed value. A stale result cannot be observed after budget
reinitialization, but it can be replaced by a command from the new session on the same budget owner.
Temporary C strings use the same nonraising, ownership-clearing discipline. Release damage after spawn success
prevents publication, poisons later runner/budget use, and cleans the armed child; release damage after a failed
spawn preserves that spawn error while poisoning later use. Release damage discovered while another exception is
propagating poisons the process-wide runner directly before reraising; it cannot depend on Ada copy-back of an
`out` parameter.

Expected spawn, duplicate, nonblocking, capture, timeout, and child-exit outcomes remain ordinary statuses when
their cleanup succeeds. Pipe close, opaque spawn-object destruction, allocation discard, or impossible ABI damage
observed on an active operation poisons its budget and the process runner. A close failure found only by a
budget-free controlled finalizer can poison only the process runner. The first primary status and exact host code
remain latched; a later cleanup failure cannot replace them. A cleanup failure with no earlier primary becomes
`Run_Cleanup_Failed`.

## Exact charge model

Charges are deterministic semantic work, not allocator or syscall timing. They are attempted in the order below,
are atomic within each reservation, and are never refunded. A denied reservation permanently exhausts the caller's
budget and publishes no candidate. Cleanup, controlled finalization, signal delivery, exact-leader reaping after a
failure, and discard are deliberately uncharged so they remain possible after exhaustion.

Every already-latched status is a zero-charge no-op. Session mismatch, inactive budget, and process-runner poison
are also zero-charge preflights. `Initialize` checks those three before its first reservation. Add and Seal check
them plus null, stale, or sealed command state before reserving; those command-state rejections are zero-charge.
`Run` checks cross-owner command/result pairing, the supplied session, budget state, and runner poison for zero
charge, then reserves its first probe before checking null, unsealed, or stale command payload. Result queries check
their latched status, supplied session, and budget state for zero charge, reserve one probe, then check missing or
stale retained payload. An undersized result-copy buffer therefore costs that one probe and no text bytes.

`Initialize` and `Add_Argument` reserve one `Work_Units` probe followed by the exact Ada string length. That covers
validation and one retained materialization. `Add_Environment` makes the same two reservations, reserves the new
entry length for its name/syntax scan, then for every retained entry reserves one comparison probe, that entry's
length, and the new name length. `Seal` reserves the argument-pointer count (`arguments + 2`) and environment-pointer
count (`environment + 1`) separately.

`Run` first reserves one command/session/gate probe. It then reserves, separately and in order, the retained
argument bytes including one C NUL per entry, the executable bytes a second time for the distinct `posix_spawn`
path materialization, the environment bytes including C NULs, the argument-pointer count, the environment-pointer
count, and fourteen fixed setup units. Those fourteen units cover one unpublished result allocation, three raw
pipe attempts, six CLOEXEC-duplication attempts, two nonblocking setup attempts, one `SIGCHLD` fact query, and one
spawn attempt. The complete fixed plan remains charged if setup stops early.

Each non-ended stdout or stderr read attempt reserves one `Work_Units`. Every positive returned count is then
attempted against `Input_Bytes` before cap comparison or retention, including the byte that proves a one-less cap.
An accepted in-cap fragment reserves its exact length in `Work_Units` before append. A child-status probe after both
pipes reach EOF reserves one `Work_Units`. Alternating capture performs at most one bounded read per non-ended stream
per turn. Result kind and length queries reserve one probe unit. A caller-buffer copy reserves that probe, reports
an undersized buffer without a text charge, and otherwise reserves the exact copied length before materialization.
Prelatched build, run, and query statuses perform no charge or mutation.

`Input_Bytes` therefore belongs only to exact bytes returned by the child. All command validation, retained and C
materialization, setup plans, observation attempts, comparisons, accepted output copies, and queries belong to
`Work_Units`. No backend or later Git layer may charge those same events again.

## Timeout and status contract

`Timeout_Milliseconds` begins immediately after successful spawn and positive-PID validation. It includes parent
descriptor handoff, incremental stdout/stderr capture, and ordinary child observation. It excludes command
construction, waiting for the process-wide gate, pipe setup, synchronous `posix_spawn`, and mandatory failure
cleanup. Clock scheduling can overshoot the requested duration. The value is therefore an execution/observation
deadline, not a hard upper bound on `Run` wall time. Ownership cleanup has priority over return; an impossible ABI,
PID, signal, or wait state deliberately fail-stops.

A prelatched `Run_Status` preserves `System_Code`. Once `Ready_To_Run` is accepted, `System_Code` is set to zero.
Only `Run_Spawn_Failed`, `Run_System_Failed`, and `Run_Cleanup_Failed` replace it with the exact host error. Completed,
foreign/stale, budget, runner-poison, invalid-command, timeout, capture-limit, allocation, and internal statuses keep
zero. A completed result may contain a nonzero exit status or terminating signal; neither is a runner failure.

## Review and verification

The architecture review cleared the ownership and runtime boundary with P0, P1, and P2 none. The first
implementation review reported P0 none and six P1 groups: the CLOEXEC gate ended before spawn, the cost model was
not closed, raw deallocation could override primary status, two index/addition expressions were not portable, and
timeout/fail-stop semantics were unstated. It also identified P2 status and coverage gaps. The gate now spans spawn;
the table above is executable in the implementation; discard is nonraising; charges and slice endpoints avoid
wrapping arithmetic; and the timeout/System_Code contract is explicit. A later lifetime audit replaced normal
reaping with nonreaping `waitid(WNOWAIT)` observation, so the exact leader continuously pins its PID and
process-group identity through cleanup.

Focused tests cover explicit environment and arguments, nonzero completion, exact stdout/stderr text, alternating
pipe-capacity-saturating capture, exact and one-less output caps, exact atomic child-input denial, spawn failure with
prior-result preservation, arbitrary Ada input bounds, duplicate environment rejection, output copies ending at
`Positive'Last`, exact builder and pre-spawn denial charge traces, cross-owner rejection, prelatched no-charge
behavior, containment of a contract-violating pipe-holding descendant on timeout and normal leader exit, and stale
result replacement after budget reinitialization. A test-only source selection pauses after gate grant, raw `pipe`,
duplicated-pipe transfer, command/result publication, first C-string ownership, and direct positive-PID publication.
Bounded abort tests prove gate fail-closed behavior and single-owner command, result, descriptor, C-string, and child
cleanup. Separate-process tests inject clean partial duplication and nonblocking setup failures,
descriptor-close damage, opaque spawn cleanup damage, release damage after an armed spawn and during exceptional
materialization cleanup, and an exception after a latched output-limit primary. They prove exact status precedence,
child cleanup, failed-spawn precedence over simultaneous cleanup damage, prior-result preservation, budget poison
where ownership is damaged, and clean runner reuse where it is not. The
disabled production hook selection uses one repository-prefixed imported-sentinel family; forced `-O0`
and `-O2` runner-object checks reject any surviving sentinel reference. The ABI
suite covers nonreaping then exact-reaping exit observation, normal and signaled wait classification, finite group
cleanup, signal reset, both unsafe `SIGCHLD` facts where the host exposes them, CLOEXEC EOF behavior, and failed-spawn
PID preservation.

The final ownership review found two Ada copy-back windows after abort was re-enabled: an `in out` scalar close slot
and an `out` duplicated-pipe record. Both now mutate aliased owner slots through not-null access parameters. One
abort test closes a descriptor, forces its number to be reused while paused, and proves finalization does not close
the replacement. Another pauses duplicated-descriptor publication and proves the actual controlled destination
closes both descriptors. The command/result abort test first retains old nonnull payloads, then proves replacement
under pending abort. Two independent final live-diff reviews report P0 none, P1 none, and P2 none.

The root runtime build/tests, Ada generator build and smoke suite, Python conformance tests, release-marker scan,
golden manifest verification, generated-fixture crate, hook-elision checks, all ten APM audit checks, and diff/line
checks pass locally on macOS. GNATformat was unavailable in the installed Alire toolchain; the compiler-enforced
110-column style check passed. The published macOS/Linux CI run remains the final platform gate.
