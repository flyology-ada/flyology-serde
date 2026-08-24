#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

GENERATOR = Path(__file__).resolve().parents[1]
REPOSITORY = GENERATOR.parents[1]
SCRIPT = GENERATOR / "generate.py"
IMPLEMENTATION = GENERATOR / "generator_impl.py"
VERIFIER_SCRIPT = GENERATOR / "verify_manifest.py"
MARKER_SCRIPT = GENERATOR / "check_release_markers.py"
TYPE_IR = GENERATOR / "vendor/type_ir/fixtures/wire-record-shape.json"
OVERLAY = GENERATOR / "tests/fixtures/wire-record-overlay.json"
GOLDEN = GENERATOR / "tests/golden"
OVERLAY_SCHEMA = GENERATOR / "schema/serde-overlay-v1.schema.json"

SPEC = importlib.util.spec_from_file_location("_serde_generator_tests", IMPLEMENTATION)
assert SPEC is not None and SPEC.loader is not None
GENERATOR_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR_MODULE)
VERIFIER_SPEC = importlib.util.spec_from_file_location("_serde_manifest_tests", VERIFIER_SCRIPT)
assert VERIFIER_SPEC is not None and VERIFIER_SPEC.loader is not None
VERIFIER_MODULE = importlib.util.module_from_spec(VERIFIER_SPEC)
VERIFIER_SPEC.loader.exec_module(VERIFIER_MODULE)
MARKER_SPEC = importlib.util.spec_from_file_location("_serde_marker_tests", MARKER_SCRIPT)
assert MARKER_SPEC is not None and MARKER_SPEC.loader is not None
MARKER_MODULE = importlib.util.module_from_spec(MARKER_SPEC)
MARKER_SPEC.loader.exec_module(MARKER_MODULE)


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode()


def run(script: Path, type_ir: Path, overlay: Path, output: Path, *extra: str):
    return subprocess.run(
        [
            "python3", str(script), "--type-ir", str(type_ir),
            "--overlay", str(overlay), "--output", str(output), *extra,
        ],
        capture_output=True,
        check=False,
        text=True,
    )


class GeneratorTests(unittest.TestCase):
    @staticmethod
    def checked_inputs():
        overlay = copy.deepcopy(GENERATOR_MODULE.load_overlay(OVERLAY).document)
        checked = GENERATOR_MODULE.load_type_ir(TYPE_IR, "fixture_shape")
        return copy.deepcopy(checked.document), overlay

    def test_fixture_generation_is_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "first"
            second = root / "second"
            self.assertEqual(run(SCRIPT, TYPE_IR, OVERLAY, first, "--test-fixture-shape").returncode, 0)
            self.assertEqual(run(SCRIPT, TYPE_IR, OVERLAY, second, "--test-fixture-shape").returncode, 0)
            self.assertEqual(
                {item.name: item.read_bytes() for item in first.iterdir()},
                {item.name: item.read_bytes() for item in second.iterdir()},
            )
            self.assertEqual(
                {item.name: item.read_bytes() for item in first.iterdir()},
                {item.name: item.read_bytes() for item in GOLDEN.iterdir()},
            )
            manifest = json.loads((first / "serde-generation.json").read_text())
            self.assertTrue(manifest["fixture_only"])
            self.assertIn(
                b"FLYOLOGY_SERDE_TEST_FIXTURE_ONLY",
                (first / "flyology-generated.ads").read_bytes(),
            )
            VERIFIER_MODULE.verify(first, require_fixture=True)

    def test_strict_is_default_and_publishes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            result = run(SCRIPT, TYPE_IR, OVERLAY, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_overlay_must_be_canonical_closed_and_fingerprint_bound(self):
        source = json.loads(OVERLAY.read_text())
        mutations = []
        unknown = dict(source)
        unknown["unknown"] = True
        mutations.append(unknown)
        stale = dict(source)
        stale["type_ir_semantic_fingerprint"] = "0" * 64
        mutations.append(stale)
        injected = json.loads(json.dumps(source))
        injected["records"][0]["fields"][0]["presentation_name"] = "line\nbreak"
        mutations.append(injected)
        overlong = json.loads(json.dumps(source))
        overlong["records"][0]["logical_type_name"] = "x" * 65
        mutations.append(overlong)
        non_ascii = json.loads(json.dumps(source))
        non_ascii["records"][0]["logical_type_name"] = "record-\N{ROCKET}"
        mutations.append(non_ascii)
        long_selected = json.loads(json.dumps(source))
        long_selected["records"][0]["ada_type"] = "A" * 49
        mutations.append(long_selected)
        stale_source = dict(source)
        stale_source["type_ir_source_sha256"] = "0" * 64
        mutations.append(stale_source)
        reserved_name = json.loads(json.dumps(source))
        reserved_name["records"][0]["ada_type"] = "Parallel.Value"
        mutations.append(reserved_name)
        bad_underscore = json.loads(json.dumps(source))
        bad_underscore["records"][0]["ada_type"] = "Bad__Name"
        mutations.append(bad_underscore)
        huge_limit = json.loads(json.dumps(source))
        huge_limit["serialization_limits"]["maximum_text_length"] = 10**100
        mutations.append(huge_limit)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index, mutation in enumerate(mutations):
                overlay = root / f"overlay-{index}.json"
                overlay.write_bytes(canonical(mutation))
                output = root / f"output-{index}"
                self.assertNotEqual(
                    run(SCRIPT, TYPE_IR, overlay, output, "--test-fixture-shape").returncode,
                    0,
                )
                self.assertFalse(output.exists())
            noncanonical = root / "noncanonical.json"
            noncanonical.write_text(json.dumps(source, indent=2) + "\n")
            self.assertNotEqual(
                run(
                    SCRIPT, TYPE_IR, noncanonical, root / "noncanonical-output",
                    "--test-fixture-shape",
                ).returncode,
                0,
            )
            duplicate = root / "duplicate.json"
            raw = OVERLAY.read_text()
            duplicate.write_text(raw.replace("{", '{"overlay_version":1,', 1))
            self.assertNotEqual(
                run(SCRIPT, TYPE_IR, duplicate, root / "duplicate-output", "--test-fixture-shape").returncode,
                0,
            )
            nonfinite = root / "nonfinite.json"
            nonfinite.write_text(raw.replace('"maximum_text_length":64', '"maximum_text_length":NaN'))
            with self.assertRaises(GENERATOR_MODULE.GenerationError):
                GENERATOR_MODULE.load_overlay(nonfinite)

    def test_vendor_digests_fail_before_generation(self):
        for relative in (
            Path("vendor/type_ir/scripts/check_fixtures.py"),
            Path("vendor/type_ir/schema/type-ir-v1.schema.json"),
            Path("vendor/type_ir/fixtures/fixtures.gpr"),
            Path("vendor/type_ir/fixtures/ada/wire_shape.ads"),
        ):
            with tempfile.TemporaryDirectory() as directory:
                copy = Path(directory) / "generator"
                shutil.copytree(GENERATOR, copy)
                with (copy / relative).open("ab") as stream:
                    stream.write(b"\n")
                output = Path(directory) / "output"
                result = run(
                    copy / "generate.py",
                    copy / "vendor/type_ir/fixtures/wire-record-shape.json",
                    copy / "tests/fixtures/wire-record-overlay.json",
                    output,
                    "--test-fixture-shape",
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("digest mismatch", result.stderr)
                self.assertFalse(output.exists())

    def test_output_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "owned"
            output.mkdir()
            sentinel = output / "user-data"
            sentinel.write_text("keep")
            result = run(SCRIPT, TYPE_IR, OVERLAY, output, "--test-fixture-shape")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), "keep")

    def test_manifest_verifier_rejects_changed_or_extra_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output"
            self.assertEqual(
                run(SCRIPT, TYPE_IR, OVERLAY, output, "--test-fixture-shape").returncode,
                0,
            )
            with (output / "flyology-generated.adb").open("ab") as stream:
                stream.write(b"\n")
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(output, require_fixture=True)

            replacement = root / "replacement"
            self.assertEqual(
                run(SCRIPT, TYPE_IR, OVERLAY, replacement, "--test-fixture-shape").returncode,
                0,
            )
            (replacement / "unmanifested.ads").write_text("package Unmanifested is end;")
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(replacement, require_fixture=True)

            extra_directory = root / "extra-directory"
            self.assertEqual(
                run(
                    SCRIPT, TYPE_IR, OVERLAY, extra_directory,
                    "--test-fixture-shape",
                ).returncode,
                0,
            )
            (extra_directory / "unmanifested").mkdir()
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(extra_directory, require_fixture=True)

            symlink_output = root / "symlink"
            self.assertEqual(
                run(
                    SCRIPT, TYPE_IR, OVERLAY, symlink_output,
                    "--test-fixture-shape",
                ).returncode,
                0,
            )
            expected_spec = symlink_output / "flyology-generated.ads"
            expected_spec.unlink()
            expected_spec.symlink_to("flyology-generated.adb")
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(symlink_output, require_fixture=True)

            special_output = root / "special"
            self.assertEqual(
                run(
                    SCRIPT, TYPE_IR, OVERLAY, special_output,
                    "--test-fixture-shape",
                ).returncode,
                0,
            )
            expected_spec = special_output / "flyology-generated.ads"
            expected_spec.unlink()
            os.mkfifo(expected_spec)
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(special_output, require_fixture=True)

            source_mismatch = root / "source-mismatch"
            self.assertEqual(
                run(
                    SCRIPT, TYPE_IR, OVERLAY, source_mismatch,
                    "--test-fixture-shape",
                ).returncode,
                0,
            )
            manifest_path = source_mismatch / "serde-generation.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["generator_source_sha256"] = "0" * 64
            manifest_path.write_bytes(canonical(manifest))
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(source_mismatch, require_fixture=True)

            nonfixture = root / "nonfixture"
            self.assertEqual(
                run(
                    SCRIPT, TYPE_IR, OVERLAY, nonfixture,
                    "--test-fixture-shape",
                ).returncode,
                0,
            )
            manifest_path = nonfixture / "serde-generation.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["fixture_only"] = False
            manifest_path.write_bytes(canonical(manifest))
            with self.assertRaises(ValueError):
                VERIFIER_MODULE.verify(nonfixture)

    def test_release_scan_rejects_fixture_artifacts_outside_allowed_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            allowed = root / "tests"
            allowed.mkdir()
            (allowed / "allowed.ads").write_text(
                "--  FLYOLOGY_SERDE_TEST_FIXTURE_ONLY\npackage Allowed is end;\n"
            )
            self.assertEqual(MARKER_MODULE.find_violations(root, allowed), [])
            (root / "escaped.ads").write_text(
                "--  FLYOLOGY_SERDE_TEST_FIXTURE_ONLY\npackage Escaped is end;\n"
            )
            (root / "serde-generation.json").write_text('{"fixture_only":true}\n')
            self.assertEqual(
                MARKER_MODULE.find_violations(root, allowed),
                [Path("escaped.ads"), Path("serde-generation.json")],
            )

    def test_initial_lowering_profile_fails_closed(self):
        root_id = "decl:wire_shape.public_record#public"
        signed_id = "decl:wire_shape.signed_16#public"

        def declaration(document, stable_id):
            return next(
                item for item in document["declarations"]
                if item["stable_id"] == stable_id
            )

        mutations = []

        document, overlay = self.checked_inputs()
        declaration(document, root_id)["facts"]["limited"]["value"]["value"] = True
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        declaration(document, root_id)["view"] = "private"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        declaration(document, root_id)["view_access"][
            "consumer_can_name_components"
        ]["value"]["value"] = False
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        document["components"][0]["default"]["present"] = True
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        declaration(document, signed_id)["shape"]["range"]["static_high"][
            "value"
        ]["value"] = str(2**63)
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        declaration(document, signed_id)["shape"]["predicate"]["status"] = "unknown"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        declaration(document, "decl:standard.boolean#public")["shape"]["predicate"][
            "value"
        ]["value"] = True
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        document["components"][0]["type"]["constraint"] = {"kind": "dynamic"}
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["records"][0]["ada_type"] = "Wire_Shape.Signed_16"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["records"][0]["fields"][0]["ada_component"] = "Signed"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["records"][0]["fields"][1]["ada_type"] = "Wire_Shape.Unsigned_16"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["records"][0]["fields"][1]["presentation_name"] = "enabled"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["output_unit"] = "Different.Consumer"
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["with_units"] = []
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        overlay["with_units"] = ["Wire_Shape", "Extra.Unit"]
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        document["context"]["effective_project"]["selected_units"] = []
        mutations.append((document, overlay))

        document, overlay = self.checked_inputs()
        document["generic_actuals"] = [{}]
        mutations.append((document, overlay))

        for document, overlay in mutations:
            with self.assertRaises(GENERATOR_MODULE.GenerationError):
                GENERATOR_MODULE.lower(document, overlay, fixture_only=True)

        document, overlay = self.checked_inputs()
        with self.assertRaises(GENERATOR_MODULE.GenerationError):
            GENERATOR_MODULE.lower(document, overlay, fixture_only=False)

    def test_overlay_schema_tracks_the_handwritten_closed_shape(self):
        source = json.loads(OVERLAY.read_text())
        schema = json.loads(OVERLAY_SCHEMA.read_text())
        self.assertEqual(set(schema["properties"]), set(source))
        self.assertEqual(set(schema["required"]), set(source))
        self.assertEqual(schema["properties"]["records"]["maxItems"], 1)
        self.assertFalse(schema["additionalProperties"])
        self.assertIn("Documentary shape only", schema["$comment"])
        self.assertEqual(
            schema["properties"]["serialization_limits"]["properties"]
            ["maximum_nesting_depth"]["maximum"],
            256,
        )

    def test_ada_string_renderer_quotes_logical_names(self):
        document, overlay = self.checked_inputs()
        overlay["records"][0]["logical_type_name"] = 'bad"name'
        overlay["records"][0]["fields"][0]["presentation_name"] = 'bad"field'
        model = GENERATOR_MODULE.lower(document, overlay, fixture_only=True)
        before = repr(model)
        _, body = GENERATOR_MODULE.render(
            model,
            {
                "generator_source_sha256": "0" * 64,
                "overlay_sha256": "0" * 64,
                "semantic_fingerprint": "0" * 64,
                "source_sha256": "0" * 64,
            },
            True,
        )
        self.assertIn('"bad""name"', body)
        self.assertIn('"bad""field"', body)
        self.assertEqual(repr(model), before)

    def test_maximum_escaped_names_keep_every_generated_line_bounded(self):
        document, overlay = self.checked_inputs()
        overlay["records"][0]["logical_type_name"] = "x" * 56
        overlay["records"][0]["fields"][0]["presentation_name"] = '"' * 28
        model = GENERATOR_MODULE.lower(document, overlay, fixture_only=True)
        spec, body = GENERATOR_MODULE.render(
            model,
            {
                "generator_source_sha256": "0" * 64,
                "overlay_sha256": "0" * 64,
                "semantic_fingerprint": "0" * 64,
                "source_sha256": "0" * 64,
            },
            True,
        )
        self.assertLessEqual(max(map(len, (spec + body).splitlines())), 110)

        overlay["records"][0]["fields"][0]["presentation_name"] = '"' * 29
        with self.assertRaises(GENERATOR_MODULE.GenerationError):
            GENERATOR_MODULE.lower(document, overlay, fixture_only=True)

    def test_with_unit_identity_is_case_insensitive_and_preserves_overlay_casing(self):
        document, overlay = self.checked_inputs()
        overlay["with_units"] = ["WIRE_SHAPE"]
        model = GENERATOR_MODULE.lower(document, overlay, fixture_only=True)
        self.assertEqual(model["with_units"], ("WIRE_SHAPE",))


if __name__ == "__main__":
    unittest.main()
