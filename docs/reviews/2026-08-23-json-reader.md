# JSON reader review — 2026-08-23

Scope: bounded pull JSON deserialization, parser/event grammar, owned decode-budget accounting, and caller-buffer
copy semantics.

## Review requirements

- Treat any uncaught exception, unchecked bound/overflow, destination-publication hazard, budget bypass, or
  writer/reader loss as P0 or P1 according to impact.
- Resolve every P0 and P1 before commit. Resolve P2 unless the accepted limitation and rationale are recorded here.
- Verify malformed JSON, Unicode escapes, integer and binary64 limits, nested failure unwind, poison/reset,
  trailing input, and caller-buffer capacity.
- Verify the borrowed source cannot escape Ada accessibility and no returned value aliases parser storage.

## Findings resolved during implementation

- P0: a `Maximum_Input_Units` failure during a Unicode escape could leave the cursor fixed while `Read_Hex`
  continued and overran a caller buffer. Pre-scans now prove remaining input capacity, every decode step stops on a
  latched error, and bounded output writes fail closed. The exact low-budget `\u0000` reproducer is retained.
- P1: string, number, and byte pre-scans could perform work beyond `Maximum_Input_Units` before charging input.
  Scans now inspect at most `Input_Remaining` bytes and report the first over-budget byte.
- P1: `IEEE_Float_64'Image` emitted only 15 significant digits and could collapse distinct binary64 values. The
  writer now emits 17 significant decimal digits, with a bit-exact adjacent-value round-trip test.
- P1: raw `Skip_Value` charged representation wrappers as logical values and containers. It now charges one
  discarded logical value while separately bounding raw JSON syntax depth, items, strings, and input work.
- P1: parsing the internal `$bytes` tag consumed the logical text-length allowance. Structural tag parsing now
  uses its fixed caller buffer without charging a text value; empty bytes decode with a zero text limit.
- P1: variant payload traversal initially routed `Next_Field` only through a record frame. It now selects record or
  variant semantics from the active frame and has an exact variant test.
- P2: `Peek_Kind` classified every number as signed, including fractional values. The documented lexical convention
  now distinguishes float, negative integer, and nonnegative integer surface forms.
- P2: typed readers returned `Syntax_Error` for an incompatible JSON surface kind. A common leading-token check now
  reports `Unexpected_Kind` before consuming the logical value.
- P2: child iteration could publish an available child at EOF, after a trailing or duplicate comma, or on another
  impossible value prefix. Optional, sequence, map, and field boundaries now validate a legal JSON value start
  before charging or publishing child availability.
- P2: invalid raw UTF-8 reported only the start of its string segment, and JSON duplicated the validator to improve
  that offset. One private serde-wide locating validator now supplies the exact byte offset to JSON and the public
  boolean UTF-8 helper without duplicating algorithms or scans.
- P2: the access-constant discriminant did not prevent the source owner from mutating through another alias. The
  contract now requires the owner to exclude mutation by aliases and tasks for the reader lifetime.
- P2: multi-character representation closers initially required adjacent bytes. Structural close tokens are now
  consumed individually, so ordinary JSON whitespace is accepted between them.
- P2: the byte tag initially matched one whitespace-free lexical prefix. The object, key, colon, string, and close
  tokens are now parsed separately; the logical tag and unescaped hexadecimal payload remain exact.

## Verification

- A forced `gprbuild -f` rebuild through the pinned Alire toolchain passes without warnings.
- The combined assertion test executable passes all logical mappings, malformed syntax, resource limits,
  poison/reset, exact scalar boundaries, and writer/reader fidelity cases.
- `git diff --check` and the explicit 110-column scan pass.
- `gnatformat` is not installed in the selected toolchain or host environment; attempts through the host and Alire
  failed before formatting. Compiler style enforcement remains active at 110 columns.
- Independent review found P0 1, P1 4, and P2 7 during iterations. Every finding above is fixed and reverified;
  the final post-fix severity sweep is recorded before commit.

## Final severity sweep

- P0: none.
- P1: none.
- P2: none.

The independent final pass found no remaining reader, writer, budget, Unicode, event-protocol, lifetime, or
losslessness issue in this checkpoint.
