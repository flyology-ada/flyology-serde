#!/usr/bin/env python3
"""Reject fixture-only generated Ada outside generator test fixtures."""

import argparse
import json
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
MARKER = "FLYOLOGY_SERDE_TEST_FIXTURE_ONLY"


def find_violations(root: Path, allowed: Path) -> list[Path]:
    root = root.resolve()
    allowed = allowed.resolve()
    violations = []
    for path in root.rglob("*.ad?"):
        if allowed in path.resolve().parents:
            continue
        if MARKER in path.read_text(encoding="utf-8", errors="strict"):
            violations.append(path.relative_to(root))
    for path in root.rglob("serde-generation.json"):
        if allowed in path.resolve().parents:
            continue
        value = json.loads(path.read_bytes())
        if isinstance(value, dict) and value.get("fixture_only") is True:
            violations.append(path.relative_to(root))
    return sorted(violations)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--allowed", type=Path)
    args = parser.parse_args()
    allowed = args.allowed or args.root / "tools/generator/tests"
    violations = find_violations(args.root, allowed)
    if violations:
        print("fixture-only generated artifacts outside tests: " + ", ".join(map(str, violations)))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
