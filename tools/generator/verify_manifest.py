#!/usr/bin/env python3
"""Verify one complete, closed Flyology serde generation directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

TYPE_IR_COMMIT = "78e6726a80d02b22f573fed3f65538cafd89fc0d"
CHECKER_SHA256 = "b2fdca4cd44c6d64a62ce0e60dd14eac049b0dac29e03bceed9232a2603a1ad2"
SCHEMA_SHA256 = "1318d40affd3a7316f79ea3ec61eada70265942bfa41fb2b6ea0f8357348bf49"
GENERATOR_VERSION = "serde-generator-v1"
FIXTURE_SOURCE_SHA256 = "92aa85c19c3d0dcfd531f42b75743559efd4f80919942a9acce5f5e15d323c4a"
FIXTURE_SEMANTIC_SHA256 = "e5f5da08e77e057960fe9ab987b3400e5557a017ae62fcdaa8d4e376042d7f76"
FIXTURE_UNIT_SHA256 = "bc190f7c3214d816d04334968cc2f651766c8b3753c229efdd6bb39c146f7f72"
MARKER = "FLYOLOGY_SERDE_TEST_FIXTURE_ONLY"
GENERATOR_SOURCE = Path(__file__).resolve().with_name("generator_impl.py")


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate manifest key: {key}")
        result[key] = value
    return result


def canonical_bytes(value: object) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def reject_constant(value: str) -> None:
    raise ValueError(f"nonfinite manifest number is not allowed: {value}")


def verify(directory: Path, require_fixture: bool = False) -> None:
    manifest_path = directory / "serde-generation.json"
    raw = manifest_path.read_bytes()
    manifest = json.loads(
        raw,
        object_pairs_hook=reject_duplicates,
        parse_constant=reject_constant,
    )
    if raw != canonical_bytes(manifest):
        raise ValueError("generation manifest is not canonical")
    expected_keys = {
        "files", "fixture_only", "generator_source_sha256", "generator_version",
        "overlay_sha256",
        "type_ir_checker_sha256", "type_ir_commit", "type_ir_fixture_unit_sha256",
        "type_ir_schema_sha256", "type_ir_semantic_fingerprint", "type_ir_source_sha256",
    }
    if not isinstance(manifest, dict) or set(manifest) != expected_keys:
        raise ValueError("generation manifest keys do not match v1")
    expected_identities = {
        "generator_version": GENERATOR_VERSION,
        "type_ir_checker_sha256": CHECKER_SHA256,
        "type_ir_commit": TYPE_IR_COMMIT,
        "type_ir_schema_sha256": SCHEMA_SHA256,
    }
    for key, expected in expected_identities.items():
        if manifest[key] != expected:
            raise ValueError(f"generation identity mismatch: {key}")
    if manifest["generator_source_sha256"] != sha256(GENERATOR_SOURCE.read_bytes()):
        raise ValueError("generation identity mismatch: generator_source_sha256")
    for key in (
        "generator_source_sha256", "overlay_sha256",
        "type_ir_semantic_fingerprint", "type_ir_source_sha256",
    ):
        if not isinstance(manifest[key], str) or not re.fullmatch(r"[0-9a-f]{64}", manifest[key]):
            raise ValueError(f"invalid generation digest: {key}")
    fixture_only = manifest["fixture_only"]
    if not isinstance(fixture_only, bool) or (require_fixture and not fixture_only):
        raise ValueError("fixture-only status mismatch")
    if fixture_only:
        fixture_identities = {
            "type_ir_fixture_unit_sha256": FIXTURE_UNIT_SHA256,
            "type_ir_semantic_fingerprint": FIXTURE_SEMANTIC_SHA256,
            "type_ir_source_sha256": FIXTURE_SOURCE_SHA256,
        }
        for key, expected in fixture_identities.items():
            if manifest[key] != expected:
                raise ValueError(f"fixture identity mismatch: {key}")
    elif manifest["type_ir_fixture_unit_sha256"] != "":
        raise ValueError("nonfixture manifest carries a fixture unit identity")

    files = manifest["files"]
    if not isinstance(files, dict) or len(files) != 2:
        raise ValueError("generation file table must contain one Ada spec and body")
    if {Path(name).suffix for name in files} != {".ads", ".adb"}:
        raise ValueError("generation file table is not an Ada spec/body pair")
    expected_directory = set(files) | {"serde-generation.json"}
    entries = list(directory.iterdir())
    actual_directory = {path.name for path in entries}
    if actual_directory != expected_directory:
        raise ValueError("generation directory contains missing or unmanifested entries")
    if any(path.is_symlink() or not path.is_file() for path in entries):
        raise ValueError("generation directory contains a non-regular entry")
    for name, digest in files.items():
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError(f"invalid output digest: {name}")
        if sha256((directory / name).read_bytes()) != digest:
            raise ValueError(f"output digest mismatch: {name}")

    spec_name = next(name for name in files if name.endswith(".ads"))
    body_name = next(name for name in files if name.endswith(".adb"))
    spec = (directory / spec_name).read_text(encoding="utf-8")
    body = (directory / body_name).read_text(encoding="utf-8")
    if (MARKER in spec) != fixture_only or (MARKER in body) != fixture_only:
        raise ValueError("fixture source marker does not match manifest")
    match = re.search(r"^package ([A-Za-z0-9_.]+) is$", spec, re.MULTILINE)
    if match is None:
        raise ValueError("generated package declaration is missing")
    expected_stem = match.group(1).casefold().replace(".", "-")
    if Path(spec_name).stem != expected_stem or Path(body_name).stem != expected_stem:
        raise ValueError("generated file names do not match the output unit")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--require-fixture", action="store_true")
    args = parser.parse_args()
    try:
        verify(args.directory, args.require_fixture)
    except Exception as exc:
        print(f"flyology-serde-manifest: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
