---
description: Preserve Flyology Serde's format boundary, resource contracts, and mandatory review workflow.
---

# Flyology Serde agent guide

`flyology_serde` is an experimental, format-agnostic Ada serialization and deserialization library. Its runtime
must remain useful independently of Flyology tasking and remoting.

## Before changing anything

- Run `git status --short --branch` and preserve unrelated work.
- Read the relevant README and design documents plus the implementation. Code and executable tests override stale
  prose.
- Use `rg` and `rg --files` for discovery and `apply_patch` for hand edits.
- Keep handwritten Ada to 110 columns and UTF-8. Run `gnatformat -P flyology_serde.gpr` on changed library sources
  and `gnatformat -P tests/tests.gpr` on changed tests.
- Run `gh` outside the sandbox. Repository: `flyology-ada/flyology-serde`.
- Keep each change focused and use one Problem/Solution commit for one reviewable semantic unit.

## Architecture and data invariants

- Keep the runtime independent of Flyology tasking, remoting, operating-system APIs, Libadalang, and
  `flyology_type_ir`. Shared Type IR and extraction are offline generator inputs, never runtime dependencies.
- Keep the logical serde traversal independent of Flyology wire codecs. Runtime visitor reuse requires separate
  evidence and review; offline structural Type IR is the only assumed shared layer.
- Do not serialize Ada record representation, padding, stream attributes, enumeration positions, access values,
  task or protected state, controlled bookkeeping, or dispatch metadata.
- Never truncate, round, or infer a lossy scalar mapping. Reject an unsupported exact mapping before output or
  destination mutation.
- Allocation, ownership, and borrowing are explicit. Bounded paths do not allocate or return unconstrained
  convenience values. Borrowed data cannot outlive its documented accessibility scope.
- A decoder owns exactly one resource budget. Charge input units, logical values, container items, text, and bytes
  exactly once at the documented backend boundary. Bound nesting, item counts, source work, path depth, and total
  work independently of source format.
- Malformed or resource-exhausting external input returns a bounded error status with a defined offset unit. It
  must not escape as an exception. Reserve exceptions for programming errors and violated preconditions.
- Deserialization builds a private unpublished candidate. Only commit publishes it; every failure aborts or resets
  candidate-owned resources, including controlled and limited values.
- Generated overlays may consume Known Type IR facts but cannot change them, replace mandatory Unknown or
  Unsupported facts, grant private representation visibility, or derive encoding from physical representation
  clauses.
- Stable wire identities, compatibility, framing, transport negotiation, and Flyology's message-wire format remain
  outside this repository.

## Verification and mandatory review

- Build the library with `alr build` and run the test crate with `alr -C tests run`.
- Add malformed, boundary, reset/cleanup, and round-trip cases for every parser or representation change.
- Review every architecture decision and every code or documentation change against its parent before considering
  it complete. Fix all P0 and P1 findings. Fix P2 findings unless the accepted limitation and rationale are
  recorded explicitly.
- After review fixes, rerun relevant formatting and tests, inspect `git diff --check` and every staged path, and
  perform a final independent diff review. Record findings and resolutions in `docs/reviews/` or the pull request.

## Commits

Use the repository Problem/Solution format:

```text
Problem: <one-line present-tense problem>

<Affected component, failure mode, and impact.>

Solution: <one-line solution>

<Changes, invariants, tests, and review evidence.>
```
