# Ada build process ABI review

## Scope

The offline Ada generator will eventually attest exact dependency Git trees by running bounded, sanitized child
processes. This change adds only the private native mechanism boundary needed by that later runner. It does not run
a child from production code, choose a deadline or resource limit, mint a generator identity, add a command-line
option, or affect the serde runtime.

Ada directly imports the fixed-signature `pipe`, `read`, `close`, `kill`, and `waitpid` calls. The C leaf retains
only host-header or C-language mechanisms: variadic `fcntl`, opaque `posix_spawn` action and attribute objects,
thread-local `errno`, wait and signal macros, and ABI layout assertions. The fixed spawn wrapper accepts only an
absolute executable, explicit null-terminated argument and environment arrays, three distinct source descriptors
above standard error, and a parent state in which every unrelated descriptor is CLOEXEC. It installs an empty child
signal mask, default catchable dispositions, and a fresh process group. Setup or spawn failure is primary. Attribute
cleanup precedes action cleanup; the first cleanup error is reported separately. Once `posix_spawn` succeeds, the
PID is always published even when cleanup reports damage, so the caller cannot lose ownership of a live child.

The raw portable `pipe` call cannot atomically set CLOEXEC. Its private Ada contract therefore requires exclusion of
concurrent process creation until both descriptors have been replaced by CLOEXEC duplicates. The later runner must
either retain that exclusion or add a separately reviewed platform binding. A failed `close` is raw and has the
platform's EINTR ambiguity; callers must never retry it blindly. Wait exit-code and signal classifiers are used only
after their corresponding predicates.

## Native-admission and SPARK audit

No retry, deadline, bounded-capture, budget, status mapping, process or descriptor ownership, process cleanup, or
publication policy is implemented in C. Those mechanisms are expressible in Ada and remain there. The C spawn leaf
necessarily owns the local initialization and fixed attribute-then-action destruction of its opaque `posix_spawn`
objects; both destruction results are returned as one deterministic secondary error. `fcntl` is variadic and its
commands are header macros; `errno` is a thread-local macro; and wait, signal, and poll constants or classifiers are
host macros. These retained leaves cannot be represented as stable direct Ada imports without recreating C-header
assumptions. The C file uses fixed signatures, repository-prefixed symbols, warnings as errors, and compile-time
failures unless `pid_t`, `ssize_t`, `errno`, and the selected Ada-compatible C scalar types match exactly.

The private Ada import package is a thin ABI declaration rather than a policy unit. There is no state machine or
arithmetic to move into SPARK in this slice. Pure classification that Ada can express remains in Ada; macro-only
wait classifiers stay as C leaves and are guarded by their Ada-side applicability rules.

## Review and verification

The proposal review initially rejected convenience wrappers around fixed-signature syscalls, an unimplementable
SIGPIPE attribution claim, missing immediate errno capture, and incomplete output transactions. The final narrowed
proposal removed SIGPIPE-safe writing and poll execution, moved fixed syscalls to direct Ada imports, added exact
C11 type assertions, and separated spawn cleanup damage from the primary spawn result. It was cleared with P0, P1,
and P2 none.

The focused ABI test checks poll-record layout declarations, nonblocking EAGAIN with immediate errno capture,
explicit argument and environment transfer, partial and zero-byte reads, failed-spawn PID preservation, child-side
CLOEXEC closure, child signal-mask and disposition reset, normal and signaled wait classification, and finite
process-group descendant cleanup. All child-owning exception paths kill the group and reap the exact unreaped leader.
Production and test projects compile C with C11, `-Wall`, `-Wextra`, and `-Werror` on macOS and Linux.

The independent implementation review initially found three P1 test-lifetime defects: child ownership was not
latched before checking secondary spawn cleanup, readiness used an unbounded read, and declarative C-string
allocation could leak. The fixes latch every successful PID immediately, use finite nonblocking readiness and EOF
probes, and allocate from null pointers only inside handled statements with nonraising discard. Its P2 review also
required the absolute-executable rule to be executable rather than prose and the native-boundary description to
acknowledge local opaque-object destruction. The C leaf now rejects a path that does not start with `/`, and the
description distinguishes that local destruction from Ada-owned process and descriptor cleanup. The narrow fix
re-review found that the initial negative test could also pass through ordinary relative-path `ENOENT`. It now
requires the host `EINVAL` macro value returned only by the leaf's structural validation. The final fix re-review
then found nullable output access formals and matching unchecked C dereferences. Required Ada output access values
are now `not null`, both C leaves validate their output pointer before any effect, and a native negative probe covers
both gates. The final live-diff re-review reports P0 none, P1 none, and P2 none.

The first published CI run then found a Linux feature-test failure before the new ABI tests: strict `-std=c11`
correctly applied to the existing `open_regular.c` leaf but hid `O_CLOEXEC` and `O_NOFOLLOW` on glibc. The reviewed
fix declares guarded `_GNU_SOURCE` at the top of that translation unit before every header, matching the new process
leaf, rather than weakening the project to `gnu11`. Its narrow proposal review reports P0 none, P1 none, and P2 none;
the implementation review also reports P0 none, P1 none, and P2 none. The strict macOS production/test build and
smoke suite pass; Linux verification remains the next published CI gate.

That Linux gate then passed the production generator build and reached the new ABI tests. Their two test-only signal
translation units lacked a feature profile, so strict C11 hid `struct sigaction`, `sigset_t`, and `sigprocmask` on
glibc. The second reviewed fix adds the same guarded `_GNU_SOURCE` definition before every header in both test files;
it changes no production source or signal semantics. Its proposal review reports P0 none, P1 none, and P2 none.
