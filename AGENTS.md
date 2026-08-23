# Flyology Serde agent guide

- Keep the crate independent of Flyology tasking, remoting, operating-system APIs, Libadalang, and
  `flyology_type_ir` at runtime.
- Keep Ada source to 110 columns and use UTF-8. Run `gnatformat -P flyology_serde.gpr` on handwritten Ada sources.
- Malformed external data returns an error status. Reserve exceptions for programming errors and violated
  preconditions.
- Do not serialize Ada record representation, padding, stream attributes, enumeration positions, access values,
  task state, protected state, or dispatch metadata.
- Allocation and borrowing must be explicit in adapter types and APIs.
- Preserve unrelated changes. Use `rg` for discovery and `apply_patch` for hand edits.
- Run `git status --short --branch` before editing and `alr build` plus `alr -C tests run` before committing.

## Mandatory review cycle

- Review every architecture decision and every change before considering it complete.
- Fix all P0 and P1 findings.
- Fix P2 findings unless a concrete rationale is documented and explicitly accepted.
- Re-run relevant formatting and tests after review fixes, then review the final diff again.
- Record review findings and their resolution in the task or pull request.
