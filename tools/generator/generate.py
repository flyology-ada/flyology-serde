#!/usr/bin/env python3
"""Execute the Flyology serde generator from one attested source read."""

from __future__ import annotations

import hashlib
import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IMPLEMENTATION = ROOT / "generator_impl.py"


def main() -> int:
    source = IMPLEMENTATION.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    with tempfile.TemporaryDirectory(prefix="flyology-serde-generator-") as directory:
        materialized = Path(directory) / "generator_impl.py"
        materialized.write_bytes(source)
        name = "_flyology_serde_exact_generator_impl"
        spec = importlib.util.spec_from_file_location(name, materialized)
        if spec is None or spec.loader is None:
            print("flyology-serde-generator: cannot load generator implementation", file=sys.stderr)
            return 1
        module = importlib.util.module_from_spec(spec)
        prior_bytecode = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        sys.modules[name] = module
        try:
            spec.loader.exec_module(module)
            module.configure_root(ROOT)
            return module.main(generator_source_sha256=digest)
        except Exception as exc:
            print(f"flyology-serde-generator: {exc}", file=sys.stderr)
            return 1
        finally:
            sys.modules.pop(name, None)
            sys.dont_write_bytecode = prior_bytecode


if __name__ == "__main__":
    raise SystemExit(main())
