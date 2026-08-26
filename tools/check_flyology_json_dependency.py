#!/usr/bin/env python3
"""Fail closed unless an Alire solution uses the reviewed Flyology JSON source."""

from __future__ import annotations

import pathlib
import json
import hashlib
import re
import sys
from typing import Optional


EXPECTED_VERSION = "0.1.0-dev"
EXPECTED_COMMIT = "3445b7540b89c3d1aa5c55d43b2817fab97710ae"
EXPECTED_URL = "git+https://github.com/flyology-ada/flyology-json.git"
EXPECTED_RELEASE_SHA256 = "a11cf63220d0244a65efd72d94c25adb09ba9443e5494d51d8487890abca2a3f"

TABLE = re.compile(r"^\[([^][]+)\]$")
ARRAY_TABLE = re.compile(r"^\[\[([^][]+)\]\]$")
ASSIGNMENT = re.compile(r"^([A-Za-z0-9_-]+)\s*=\s*(.+)$")


def scalar(text: str) -> object:
    if text in {"true", "false"}:
        return text == "true"
    if text.startswith('"'):
        value = json.loads(text)
        if not isinstance(value, str):
            raise ValueError("expected a TOML basic string")
        return value
    raise ValueError(f"unsupported lock scalar {text!r}")


def read_states(path: pathlib.Path) -> list[dict[str, object]]:
    """Read the closed scalar subset used by Alire solution states.

    macOS's system Python is 3.9, so this checker deliberately does not rely
    on tomllib. Unknown tables and multiline arrays are ignored; duplicate or
    malformed scalar keys in a state fail closed.
    """

    states: list[dict[str, object]] = []
    current: Optional[dict[str, object]] = None
    target: Optional[dict[str, object]] = None

    with path.open("r", encoding="utf-8") as source:
        for number, raw_line in enumerate(source, 1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            array_table = ARRAY_TABLE.match(line)
            if array_table:
                if array_table.group(1) == "solution.state":
                    current = {"release": {"origin": {}, "dependencies": []}}
                    states.append(current)
                    target = current
                elif (
                    current is not None
                    and array_table.group(1)
                    == "solution.state.release.depends-on"
                ):
                    release = current["release"]
                    assert isinstance(release, dict)
                    dependencies = release["dependencies"]
                    assert isinstance(dependencies, list)
                    dependency: dict[str, object] = {}
                    dependencies.append(dependency)
                    target = dependency
                else:
                    target = None
                continue

            table = TABLE.match(line)
            if table:
                name = table.group(1)
                if current is not None and name == "solution.state.release":
                    target = current["release"]  # type: ignore[assignment]
                elif current is not None and name == "solution.state.release.origin":
                    release = current["release"]
                    assert isinstance(release, dict)
                    target = release["origin"]  # type: ignore[assignment]
                else:
                    target = None
                continue

            assignment = ASSIGNMENT.match(line)
            if target is None or assignment is None:
                continue
            value_text = assignment.group(2)
            if value_text.startswith("["):
                continue
            key = assignment.group(1)
            if key in target:
                raise ValueError(f"{path}:{number}: duplicate scalar key {key!r}")
            try:
                target[key] = scalar(value_text)
            except (ValueError, json.JSONDecodeError) as error:
                raise ValueError(f"{path}:{number}: {error}") from error

    return states


def release_manifest_from_text(text: str) -> bytes:
    normalized = text.replace("\r\n", "\n")
    if "\r" in normalized:
        raise ValueError("lock contains unsupported carriage returns")
    blocks = normalized.split("[[solution.state]]\n")
    matching = [block for block in blocks[1:] if block.startswith('crate = "flyology_json"\n')]
    if len(matching) != 1:
        raise ValueError(f"expected one Flyology JSON state block, found {len(matching)}")
    marker = "[solution.state.release]\n"
    if marker not in matching[0]:
        raise ValueError("Flyology JSON state has no release manifest")
    release = matching[0][matching[0].index(marker) :].rstrip() + "\n"
    return release.encode("utf-8")


def check_lock(
    path: pathlib.Path, expected_release_sha256: str = EXPECTED_RELEASE_SHA256
) -> None:
    text = path.read_text(encoding="utf-8")
    all_states = read_states(path)
    states = [
        state
        for state in all_states
        if state.get("crate") == "flyology_json"
    ]
    if len(states) != 1:
        raise ValueError(f"expected one flyology_json solution state, found {len(states)}")

    state = states[0]
    release = state.get("release", {})
    origin = release.get("origin", {})
    dependencies = release.get("dependencies", [])
    expected_versions = f"={EXPECTED_VERSION}"
    problems: list[str] = []

    if state.get("pinned") is not False:
        problems.append("dependency must be an unpinned indexed release")
    if state.get("versions") != expected_versions:
        problems.append(
            f"constraint is {state.get('versions')!r}, expected {expected_versions!r}"
        )
    if release.get("version") != EXPECTED_VERSION:
        problems.append(
            f"resolved version is {release.get('version')!r}, expected {EXPECTED_VERSION!r}"
        )
    if origin.get("commit") != EXPECTED_COMMIT:
        problems.append(
            f"source commit is {origin.get('commit')!r}, expected {EXPECTED_COMMIT!r}"
        )
    if origin.get("url") != EXPECTED_URL:
        problems.append(f"source URL is {origin.get('url')!r}, expected {EXPECTED_URL!r}")
    if dependencies != [{"gnat": ">=13 & <17"}]:
        problems.append(
            f"release dependencies are {dependencies!r}, expected only the reviewed GNAT constraint"
        )

    crate_names = {state.get("crate") for state in all_states}
    allowed_names = {"flyology_json", "gnat", "flyology_serde"}
    unexpected = crate_names - allowed_names
    if unexpected:
        problems.append(f"unexpected solution states: {sorted(unexpected)!r}")
    release_sha256 = hashlib.sha256(release_manifest_from_text(text)).hexdigest()
    if release_sha256 != expected_release_sha256:
        problems.append(
            f"release metadata SHA-256 is {release_sha256}, expected {expected_release_sha256}"
        )

    if problems:
        joined = "; ".join(problems)
        raise ValueError(f"{path}: unreviewed Flyology JSON dependency: {joined}")

    print(f"{path}: reviewed Flyology JSON {EXPECTED_VERSION} at {EXPECTED_COMMIT}")


def main(arguments: list[str]) -> int:
    if not arguments:
        print("usage: check_flyology_json_dependency.py LOCK [LOCK ...]", file=sys.stderr)
        return 2

    try:
        for argument in arguments:
            check_lock(pathlib.Path(argument))
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
