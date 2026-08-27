# Reflection serialization experiment

This uninstalled experiment implements the reviewed generic Reflection serialization adapter while
`flyology_reflection=0.1.0-dev` is not yet available through the Flyology Alire index. It is not part of the root
Serde project or installed source closure, and it is not a production dependency or release.

Run it against a local reviewed Reflection checkout:

```sh
FLYOLOGY_REFLECTION_ROOT=/path/to/flyology-reflection scripts/test.sh
```

The script supplies GPR search paths only for this experiment. No committed Alire manifest contains a Git or path
pin. It exports the exact reviewed Reflection commit into a fresh directory, runs the positive integration, proves
that a mismatched source type and observation procedure cannot instantiate the generic adapter, and scans both build
closures for forbidden dependencies. Promotion to the separate `flyology_serde_reflection` crate requires the
indexed source and every gate in `docs/reviews/2026-08-27-reflection-derivation-proposal.md`.
