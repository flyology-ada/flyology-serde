# Ada local source snapshot proposal

Date: 2026-08-26

Status: private implementation checkpoint under mandatory change review. It selects no production limits and
creates no production generation authority. The body and focused normal/fault/abort tests exist; parent-stage
integration remains absent and fail-closed.

The concrete private checkpoint is in
`flyology_serde_generator-build_attestations-local_snapshots.ads` and
`flyology_serde_generator-build_attestations-file_abi.ads`, with the implementation in the matching body and the
header-dependent C declarations in `native/open_regular.c`. No parent operation references these units, and
`Create_Checked_Stage` remains fail-closed while this checkpoint is reviewed.

## Scope

The next Ada-authoritative generator milestone is a private local-source snapshot owner beneath
`Flyology_Serde_Generator.Build_Attestations`. It opens one caller-selected generator root, then captures retained
bytes and SHA-256 identities for portable relative paths supplied by the already reviewed `Source_Lists` owner.
It is a transitional Serde-private implementation until the Type IR offline-support crate publishes equivalent
reviewed Ada resource owners.

This slice does not discover the closed source set, parse provenance, inspect Git dependencies, construct a build
stage, publish a generator, or create extraction authority. A later parent transaction must perform independent
closed-set discovery and exact bidirectional comparison before a `Checked_Stage` can exist. The current
`Create_Checked_Stage` remains fail-closed. No constructor or conversion from this package is accepted by a stage
or production-authority type.

## Private Ada surface

Add the private child `Flyology_Serde_Generator.Build_Attestations.Local_Snapshots` with two limited owners:

- `Root` retains one no-follow directory descriptor and the exact build-budget session;
- `File_Snapshot` retains one relative path, exact same-handle bytes, lower-case SHA-256, and the final regular-file
  identity observed from that handle.

`Open_Root` accepts the already validated absolute generator-root pathname, the active session, and the caller's
existing source path, directory-depth, per-file, and aggregate-byte limits. It stores those limits and owns the
aggregate accepted-source-byte count so a caller cannot reset or understate it between captures. It rejects a final
symlink or non-directory and publishes the owner only after all checks succeed. `Capture` accepts that retained
`Root`, one portable relative path, the active session, and an empty `File_Snapshot` whose discriminant designates
the same exact `Budget`. It walks every relative component from the retained root descriptor with no symlink
following, requires intermediate components to be directories and the final component to be a regular file, reads
that exact descriptor through EOF or the first denied extra octet, hashes exactly the accepted bytes, verifies
stable final metadata on the same handle, independently rewalks and reopens the logical path no-follow from the
retained root, requires that verifier to name the same unchanged regular identity, and requires successful close of
every transient descriptor before publication.

Before any path-dependent operating-system call, `Capture` reserves its own path-observation work and defensively
requires the same closed relative grammar as `Source_Lists`: nonempty portable ASCII, no NUL or platform separator
alias, no leading or trailing `/`, no empty, `.` or `..` component, and no repeated `/`. It also counts directory
components below the root and applies the retained `Maximum_Directory_Depth`; the final regular-file component does
not add directory depth. Production receives only paths borrowed directly from the retained source-list owner; the
defensive check cannot grant membership to an independently supplied string.

The package exposes retained path, byte length, bytes, and digest only through scalar-length and caller-buffer copy
queries. Byte-copy uses a zero-based `Unsigned_64` offset and an arbitrary-bound caller stream-element array; path
copy uses an arbitrary-bound caller `String`. A query changes its status output but preserves every data output on
a normally returned non-success status. If the final commit raises or a pending task abort is delivered immediately
after its abort-deferred publication region, the caller outputs are unspecified and must be discarded. The package
exposes no descriptor, access value, borrowed view, allocating `String` getter,
pathname-based reopen helper, trust Boolean, or caller-mintable checked marker. File identity remains private; a
later reviewed parent may receive an owner-to-owner equality query, never its native representation.

The byte-copy query accepts offsets `0 .. Byte_Length`. At `Byte_Length` it returns `End_Of_Bytes` after the query
probe and preserves buffer/count/completion outputs; a larger offset is `Invalid_Offset` with the same preservation.
A null buffer before the end is `Output_Too_Small`. A nonnull buffer copies exactly
`min (Buffer'Length, Byte_Length - Offset)` bytes, reports `Written` as a lower-bound-independent count, sets
`Complete` exactly when that copy reaches `Byte_Length`, and succeeds even when the retained suffix is larger than
the buffer. Path and digest copies are whole-value operations: an undersized buffer reports `Output_Too_Small` and
copies nothing; success copies the complete value and reports a count. A prelatched non-success query status remains
a zero-charge no-op; otherwise the procedure always publishes its resulting query status.

Both limited owner types have a nonnull `Budget` access discriminant and retain the exact creating session.
`File_Snapshot` also retains the root's private opened-directory identity. `Capture` first requires `Root.Owner` and
`File_Snapshot.Owner` to designate the same exact budget, then requires the supplied session to match that budget,
then verifies each retained payload's stored session before reading another field. A default/failed owner is not
observable. Caller-buffer queries create no cursor, view, callback latch, or reusable lease, so cross-owner, stale,
nested, and reentrant observation cannot be expressed.
The existing `Build_Budgets` contract forbids concurrent use of one budget from multiple tasks. Root, capture, and
query operations inherit that serialization boundary; this private package adds no lock or alternate task owner.

The private statuses distinguish prelatched no-op, foreign budget/session, nonempty owner, path-length limit,
malformed relative path, root/open/type/read/close/changed failures, directory-depth, per-file, or aggregate limit
exhaustion, budget
exhaustion, budget failure, allocation failure, output-too-small, end-of-bytes, and invalid-offset query outcomes, and
internal failure.
The first primary status survives cleanup. An unexpected cleanup defect poisons an active budget but does not
replace an earlier exhausted state.
The statuses are the complete diagnostic surface: the package allocates or materializes no diagnostic text.

## Native boundary

Extend the generator's existing `open_regular.c` ABI leaf only for header-defined filesystem mechanisms that direct
Ada imports cannot express portably:

- open an absolute directory with `O_RDONLY`, `O_CLOEXEC`, `O_NOFOLLOW`, and `O_DIRECTORY`;
- open a child directory with `openat`, `O_RDONLY`, `O_CLOEXEC`, `O_NOFOLLOW`, and `O_DIRECTORY`;
- open a final unknown candidate with `openat`, `O_RDONLY`, `O_CLOEXEC`, `O_NOFOLLOW`, `O_NONBLOCK`, and `O_NOCTTY`, then accept
  only a regular `fstat` result. This makes a FIFO open prompt; it does not claim that `O_NONBLOCK` prevents every
  device driver or block-device open from blocking. The trusted/quiescent source-root precondition excludes an
  adversary placing such special nodes in the selected tree;
- extract `st_dev`, `st_ino`, `st_size`, nanosecond `mtime`/`ctime`, and the directory/regular classification from
  `fstat` through separate fixed scalar outputs after compile-time width and signedness checks. No C aggregate
  layout crosses the Ada boundary.

Ada directly imports fixed-signature `read` and `close`. Ada owns path grammar, component walking, limits, charging,
read sequencing, identity comparison, hashing, allocation, status precedence, and cleanup. The C leaf contains no
retry, policy, state machine, ownership transfer, or status classification.

The leaf also exposes immediate `errno` capture and the header-defined `EINTR` classifier. Ada retries interrupted
`open`, `openat`, `fstat`, and `read` operations only after a fresh attempt charge; every other error fails. A
zero-byte read is EOF and a short positive read is accepted before the next separately charged attempt. Close uses
the existing reviewed `Close_Once` rule: exactly one uncharged attempt, never retry (including `EINTR`), and make
the Ada descriptor slot invalid in the same abort-deferred commit on every return. A failed close is an ambiguous
resource failure; it is never passed to another close and may remain until process exit.

## Identity and mutation contract

`Root` authenticates the opened directory object, not the text pathname's ancestors. Every descendant open is
relative to its retained descriptor. The relative path cannot escape the root and no component may be a symlink.
The file descriptor names one regular object for the whole read. Capture samples identity and nonnegative size
before reading, reads through EOF while within both limits or rejects after the first positive batch crossing a
limit, then samples identity and metadata again. Device, inode, type, size, `mtime`, and `ctime` must remain equal,
and final size must equal the bytes read. While the original final descriptor remains retained, Capture performs a
second complete no-follow walk from `Root`, opens the current final path, and requires its full metadata to equal
the final same-handle sample. Every verifier and intermediate descriptor and the original final descriptor must
close successfully before publication.

This detects a path replacement visible to the second walk, truncation, growth, and observed same-handle metadata
changes. A replacement after the verifier observation and a writer that changes bytes while restoring all sampled
metadata remain outside one capture. The future source transaction therefore
must run two independent no-follow discovery/capture passes around staging and compare ordered relative paths,
identities, byte lengths, digests, and bytes. Neither one capture nor two matching snapshots proves hostile
filesystem immutability; the trusted/quiescent generator-root parent assumption from the accepted build-attestation
proposal remains required.

Root acquisition follows ordinary resolution for ancestor components and applies no-follow to the final root
component. It therefore makes no no-follow-ancestry claim. A future parent requiring ancestry attestation must walk
from a separately trusted anchor and may not infer that property from `Root`.

The package remains a private child, is not installed independently, and introduces no public lock, resource,
identity, digest, or authority type. It has no JSON, Type IR, Wire, runtime, or Libadalang dependency. Once Type IR
publishes a reviewed Ada offline-support owner with equivalent no-follow identity, same-read, budget, and lifecycle
semantics, Serde will replace this child at the generator boundary and delete it after parity tests pass. It will
not preserve this helper as a compatibility facade or shared Flyology abstraction.

## Limits and exact accounting

The package introduces no default or visible capacity. `Root` retains the active request's `Maximum_Path_Bytes`,
`Maximum_Directory_Depth`, `Maximum_Source_Bytes_Per_File`, and `Maximum_Total_Source_Bytes`. Its aggregate starts
at zero, is advanced with checked arithmetic only in the same abort-deferred commit that publishes a successful
`File_Snapshot`, and cannot be supplied, reset, or decreased by a caller. Every amount uses checked conversion to
the existing positive `Build_Budgets.Charge_Amount`.

The v1 operation trace is:

1. A prelatched status, unequal owner discriminants, foreign session, exhausted budget, failed budget,
   invalid/nonempty owner, or stale retained payload is a zero-charge rejection, in that order. Exhausted reports
   the operation's budget-exhausted status; failed reports budget-failed. Exact limit equality remains admissible.
2. `Open_Root` reserves one `Work_Units` path probe, applies the retained path-length limit, then reserves exact
   nonzero pathname bytes before its local C-string materialization and defensive absolute-path scan. It reserves
   one `Work_Units` before every actual open or `fstat` attempt, including each `EINTR` retry.
3. `Capture` reserves one `Work_Units` path probe, applies `Maximum_Path_Bytes`, then reserves exact nonzero relative
   path bytes before grammar scanning and component materialization. A length excess has its own status and no
   path byte is reserved or inspected. That scan also applies directory depth. It
   reserves one `Work_Units` before every actual `openat` or `fstat` attempt in both walks, including retries.
4. Each actual read attempt reserves one `Work_Units` before `read`, including an `EINTR` retry and the zero-byte EOF
   attempt.
5. Every positive returned batch reserves its exact length once in `Input_Bytes` before append or hash. This debit
   occurs before the per-file and aggregate cap checks, so a denied extra batch is observable and never refunded.
   Aggregate remaining subtracts both the root's previously accepted bytes and the current unpublished file's
   running total. Per-file limit failure has precedence when the same batch crosses both limits; aggregate failure
   is otherwise next. Equality succeeds, so an empty file still performs its charged EOF read when the aggregate
   equals its cap.
6. An accepted positive batch reserves its exact length once in `Work_Units` before copying it from the transient
   read buffer into unpublished fixed blocks and updating SHA-256. No zero-byte reservation is made.
7. Every final same-handle or verifier metadata observation and every verifier open follows the attempt rule above.
   Close and cleanup are uncharged, but successful close of every transient descriptor is mandatory for publication.
8. Each scalar or retained-length query reserves one `Work_Units`. A path or digest copy reserves one probe,
   validates caller capacity, then reserves the exact nonzero copied bytes before materialization. A byte copy
   reserves one probe and validates range/capacity. Cost-model v1 fixes `Block_Bytes = 4_096`; zero retained bytes
   use no block, every nonfinal block is exactly `Block_Bytes`, and a final block contains `1 .. Block_Bytes`
   bytes. Let `L = Byte_Length`, `O = Offset`, and
`R = L - O` after establishing `O < L` and a nonnull buffer. It first computes
`C = min (Into'Length, R)` without converting an oversized length. The body has compile-time requirements that
`Stream_Element_Offset'Size <= Unsigned_64'Size`, `Stream_Element_Offset'First < 0`, and
`Stream_Element_Offset'Last >= 0`. The signed type's positive Last is therefore strictly below `Unsigned_64'Last`,
so `Unsigned_64 (Last) + 1` is representable. If `Into'First` and
`Into'Last` span that subtype's complete range, the implementation computes
`Negative_Count = Unsigned_64 (-(Stream_Element_Offset'First + 1)) + 1` and
`Nonnegative_Count = Unsigned_64 (Stream_Element_Offset'Last) + 1`. Both conversions occur before the final
additions, so the minimum signed bound is never directly negated and neither `+ 1` is evaluated in the signed type.
It checks their sum against `Unsigned_64'Last`. Only an overflowing sum denotes a mathematical cardinality of
`Unsigned_64'Last + 1`, in which case `C = R`; a representable sum participates in the ordinary minimum. Every
proper subrange has at least one fewer element than the complete range, fits `Unsigned_64`, and is converted
directly. Before any further reservation, `C - 1` must fit `Stream_Element_Offset`; failure reports
`Allocation_Failed` without poisoning. Checked endpoint arithmetic then proves
`Into'First + Stream_Element_Offset (C - 1) <= Into'Last`. It computes
   `Last_Byte = O + C - 1`, which cannot overflow because `C <= L - O` and therefore `Last_Byte < L`, and
   `V = 1 + Last_Byte / Block_Bytes`. `V` counts every linked node examined from the head through the last copied
   block. The operation atomically reserves exactly `V` `Work_Units`, then exactly `C` staging `Work_Units`, then
   exactly `C` publication `Work_Units`, with no coalescing or refund. All three grants precede allocation,
   traversal, or output mutation. Visit denial performs no byte reservation; staging denial retains the visit
   debit; publication denial retains both earlier debits. None of those denials traverses or writes output. It
   neither traverses nor charges a block when the offset is at the retained end or invalid. A
   too-small buffer or end offset reports its specific status after the probe and performs no traversal or further
   reservation. `V` and `C` are checked before conversion to `Charge_Amount`. The exact-`C` unpublished automatic
   scratch has bounds `0 .. Stream_Element_Offset (C - 1)`. An already initialized Boolean lives in an enclosing
   handled scope. An inner block contains Scratch as its sole dynamic declaration and sets the outer Boolean in its
   first statement. Ada propagates a `Storage_Error` raised while elaborating that inner declaration to the outer
   handler while the Boolean remains false, which maps to `Allocation_Failed`. A later `Storage_Error` reaches the
   same handler with the Boolean true, is an internal failure, and poisons the session. Scratch
   elements are elementary and the scope has no access owner, explicit deallocation, controlled object, finalizer,
   or cleanup hook. Scope exit therefore performs no user cleanup that could fail, leak heap ownership, or revise a
   published result. Traversal fills and validates exactly `C` elements under the `V + C` debit. The final `C`
   debit covers publication into the already validated caller prefix.

All reservations are atomic, ordered, and never refunded. Denial precedes the named effect and leaves the
destination owner empty. Already consumed input and work remain charged after any later failure. The parent, not
this package, owns source-file count, discovered-entry, discovered-path, manifest, stage-write, and projection
charges.

Status-only failures and nonraising cleanup use no ledger charge. A query reserves its complete required work before
copying; denial leaves every caller data output and the owner unchanged while publishing its status result. Accepted
reservations remain consumed after any later failure. After every potentially failing operation, byte copy performs one
abort-deferred assignment to
`Into (Into'First .. Into'First + Stream_Element_Offset (C - 1))`, followed by `Written`, `Complete`, and
success-status commit with no calls or hooks. The earlier endpoint proof establishes that the target last bound is
within `Into'Last`. Abort is deferred, test-only precommit observation completes, and then the body sets
`Commit_Started` immediately before the first persistent mutation. Every exception before that phase may be
classified into a normally returned failure only while outputs remain unchanged. Once the phase is
set, the enclosing handler propagates every exception instead of translating it to a status. A commit exception or
a pending abort delivered immediately after that region is therefore an abnormal transfer and does not promise
output rollback. Leaving the automatic elementary scratch scope performs no product cleanup call or hook.

## Ownership and failures

Every allocation and descriptor is attached immediately to a local limited controlled candidate. Abort is deferred
before each `open`/`openat` call and remains deferred through attaching a successful descriptor. Every `close` call
and descriptor-to-invalid transition is likewise one abort-deferred `Close_Once` commit, so finalization cannot
double-close a reused descriptor. Candidate-to-owner and aggregate-count transfers are one final abort-deferred,
hook-free, call-free commit with no later fallible work. Capture assigns the conservative aggregate first, publishes
the snapshot second, and detaches the guard last. An abnormal transfer after that commit starts makes both root and
snapshot discard-only. Task abort otherwise propagates after nonraising finalization closes descriptors
and frees unpublished storage. A failed replacement preserves an earlier snapshot; this initial API instead
requires an empty destination so accidental reuse is explicit.

A close failure rejects the candidate and is test-injectable. If a read, limit, budget, or metadata failure is
already primary, later cleanup damage remains secondary. Failure cleanup never follows a pathname. It closes only
retained descriptors and frees owned memory. Every root, snapshot, and unpublished candidate retains the exact
session under which it acquired cleanup-owned resources. After a descriptor close failure during finalization,
cleanup calls `Build_Budgets.Poison` only when `Build_Budgets.Matches` confirms that retained session is still the
budget's current session; `Poison`, not `Matches`, performs the `Active`-state gate and preserves an already exhausted
or failed state. Cleanup never poisons a later session after the caller has reinitialized the same budget object.
Stale-session cleanup is still nonraising, performs no ledger operation, and retains no false authority. The package
cannot delete or publish filesystem objects. A later stage cleanup must retain an ambiguous by-name artifact rather
than delete it when identity cannot be proven.

Retained bytes use a linked sequence of body-private blocks whose cost-model-v1 capacity is exactly 4,096 bytes.
Append fills the current tail before allocating another block, so every nonfinal block is full and only the final
block may contain 1 .. 4,096 bytes. A positive read first lands in a transient fixed buffer; after input and work
reservations, bytes are copied exactly once into unpublished blocks. There is no growth reallocation or uncharged
recopy. Block capacity is offline cost-model geometry, not a public storage, schema, or authority value. The
initial signed `st_size` is only a hint and must be
nonnegative and representable as `Unsigned_64`; no allocation trusts it. Read request sizing takes the minimum of
the transient buffer and one beyond the smaller remaining limit without speculative addition: when the remaining
value is at least the transient capacity, request exactly that capacity; otherwise compute checked
`remaining + 1` (including zero to one). Convert the already bounded result to `size_t` only after its range check.

## Required verification

The freeze gate requires tests covering null and arbitrary Ada bounds; exact and one-extra path, directory-depth,
per-file, aggregate-input, and
work limits; aggregate equality with an empty file; empty and binary files; non-UTF-8 octets; final and intermediate
symlinks; a final FIFO with no writer returning promptly; a final terminal device rejected without changing
controlling-terminal state; promptly rejected known special-file finals without a universal device-open latency
claim; `.`/`..`, empty, absolute,
repeated-separator, and nonportable relative paths; root replacement after opening; file replacement before and
after the initial final open; every observed identity, type, size, `mtime`, or `ctime` change; truncation/growth and
same-handle mutation hooks; short reads, charged `EINTR` retries, zero-read EOF, and read failure; close failure or
`EINTR` with no retry at every intermediate/verifier/final position; prior-owner and query-output preservation;
cross-session and cross-budget use; deterministic complete charge traces; digest parity; cleanup faults; and
stale-owner finalization after reinitializing the same budget session; pending abort at every descriptor attach,
close commit, allocation, aggregate update, and owner transfer. The focused native ABI test verifies the
compile-time `ssize_t`/Ada `C.long` match and `off_t`/`dev_t`/`ino_t` conversions, fixed scalar identity widths,
nanosecond-domain rejection, errno classification, and file-type classification on macOS and Linux.

Copy trace tests include offsets 0, `Block_Bytes - 1`, `Block_Bytes`, `Block_Bytes + 1`, and the final byte; a
partial caller buffer crossing a block; null buffer; end and invalid offsets; denial at each of the `V`, staging
`C`, and publication `C` reservation prefixes; allocation failure after all three grants; invariant failure after
staging; a source gate proving there is no scratch deallocation/finalization/cleanup hook; exact successful
`1 + V + 2 * C` total work including the query probe; exact and one-less budgets; arbitrary and
`Positive'Last` destination bounds; task abort before and during the final publication region; caller discard after
post-commit abort; and the `Unsigned_64`, `Stream_Element_Offset`, and `C - 1` conversion boundaries. Every normally
returned rejected query preserves the caller buffer, Written, and Complete.

The current focused tests cover normal large/empty/known-answer captures, independent SHA-256 for `abc`, exact and
one-less path/depth/per-file/aggregate/input/work limits, aggregate equality with an empty file, normally returned
root/capture owner and aggregate preservation, prior-owner preservation, open/fstat/read/close/allocation faults,
exact baseline and one-less `open`/`read` `EINTR` charges, exact capped-short-read attempt charges, reset/consumption
of occurrence-indexed hooks, descriptor/block/path/payload allocation-release parity, continue-through-chain
cleanup after injected release damage, stale-session cleanup, byte-boundary copies, V/C/C denial, and
root/capture/copy precommit abort with task-termination, retained-owner cleanup, and matching-session evidence.

The remaining freeze gates include concurrent platform mutation/replacement/truncation/growth, terminal and other
special devices, cross-budget and cross-session calls, intermediate-directory open/close fault positions, every
descriptor-attach/close/allocation abort edge, path/digest and remaining scalar-query exact/one-less budgets, real
allocator/deallocator and invariant failures beyond the static hooks, ABI-width and extreme conversion boundaries,
and the rest of the platform matrix above. This document does not treat the present diff as frozen.

Implementation and every corrective diff receive independent P0/P1/P2 review. P0/P1 must be fixed, and P2 is
fix-by-default. Only a later reviewed parent transaction may connect this owner to `Create_Checked_Stage`.
