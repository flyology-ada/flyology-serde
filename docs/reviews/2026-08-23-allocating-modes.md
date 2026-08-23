# Allocating modes and root transaction review — 2026-08-23

Scope: whole-document commit ordering, copied JSON/CBOR input ownership, explicitly allocating text and byte
candidates, failure cleanup, configured ceilings, documentation, and executable integration coverage.

## Review rule

Architecture and implementation received independent adversarial review. Every P0, P1, and P2 finding was fixed
and re-reviewed. The final verdict was P0 none, P1 none, P2 none, with commit clearance.

## Findings resolved

- P1: trailing-input validation previously sat outside the generic candidate transaction. `Finish_Document` is now
  an abstract deserializer operation called after value traversal and before commit. A status or exception rolls
  back the unpublished candidate. Nested combinators never finish a document.
- P1: a copied input could allocate before the backend rejected a known over-limit source. Both snapshot facades
  compare source length with `Maximum_Input_Units` before allocation and report the first disallowed byte offset.
- P1: snapshot cleanup could become unsafe if a future reader finalizer outlived its source. The borrowed reader now
  occupies a nested scope that ends before the standard-heap snapshot is freed; exception cleanup frees exactly once.
- P1: byte-vector serialization narrowed `Count_Type` to `Natural` before checking a latched status. It now performs
  the no-op guard first, compares discrete positions with the positive stream-offset extent, and converts only after
  proving the value representable.
- P2: allocating-package names and prose could imply ownership transfer, custom allocators, exact container capacity,
  or complete arbitrary-value allocating builders. `Copied_Input` states snapshot semantics, standard-heap packages
  state their eager maximum-sized scratch cost, and documentation distinguishes exact candidate contents from
  implementation-defined container capacity and application-owned record/map/array builders.
- P2: initial success tests used a counting serializer that ignored payloads. Final tests assert exact bounded JSON
  and CBOR output in addition to latched-error zero-event behavior.

## Accepted contracts

- `Deserialization_Adapters.Deserialize` is a root-only whole-document transaction:
  begin, traverse, finish document, commit. Any earlier status or exception invokes rollback.
- `JSON.Copied_Input` and `CBOR.Copied_Input` copy rather than take source ownership, use exactly the adapter policy,
  and retain no source or reader after the synchronous call.
- `Allocating_Text` and `Allocating_Bytes` are candidate adapters over the bounded copy interface. They eagerly
  allocate scratch equal to the configured maximum and may transiently hold scratch plus the owned candidate.
- Standard-heap `Storage_Error` propagates after local scratch cleanup and outer candidate rollback. Format and
  configured-capacity failures remain statuses; vector index-capacity failure maps to `Capacity_Exceeded`.

## Verification

- A forced full warning-visible rebuild completed successfully.
- The assertion-enabled test binary was rebuilt after the final source change and completed successfully.
- Tests cover finish-before-commit, status/exception rollback, nested non-finalization, JSON and CBOR trailing input,
  source max/max+1 preflight and offsets, non-1 CBOR bounds, zero/exact/over-limit text and bytes, injected copied-input
  candidate exceptions, latched-error no-op behavior, and exact allocating serialization output.
- `git diff --check` and the 110-column Ada scan passed.

GNATformat was unavailable in the environment. Compiler style checks and the explicit line-length scan were used for
the handwritten Ada sources.
