#!/usr/bin/env python3
"""Fail-closed Flyology serde adapter generator for reviewed Type IR v1."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping, NamedTuple

TYPE_IR_COMMIT = "78e6726a80d02b22f573fed3f65538cafd89fc0d"
CHECKER_SHA256 = "b2fdca4cd44c6d64a62ce0e60dd14eac049b0dac29e03bceed9232a2603a1ad2"
SCHEMA_SHA256 = "1318d40affd3a7316f79ea3ec61eada70265942bfa41fb2b6ea0f8357348bf49"
GENERATOR_VERSION = "serde-generator-v1"
ROOT = Path(__file__).resolve().parent
VENDOR = ROOT / "vendor" / "type_ir"
CHECKER = VENDOR / "scripts" / "check_fixtures.py"
TYPE_IR_SCHEMA = VENDOR / "schema" / "type-ir-v1.schema.json"
SELECTED_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)*$")
RESERVED = {
    "abort", "abs", "abstract", "accept", "access", "aliased", "all", "and",
    "array", "at", "begin", "body", "case", "constant", "declare", "delay",
    "delta", "digits", "do", "else", "elsif", "end", "entry", "exception",
    "exit", "for", "function", "generic", "goto", "if", "in", "interface",
    "is", "limited", "loop", "mod", "new", "not", "null", "of", "or",
    "others", "out", "overriding", "package", "private", "procedure",
    "parallel", "pragma", "protected", "raise", "range", "record", "rem",
    "renames", "requeue",
    "return", "reverse", "select", "separate", "some", "subtype", "tagged",
    "synchronized", "task", "terminate", "then", "type", "until", "use",
    "when", "while", "with", "xor",
}
FIXTURE_SOURCE_SHA256 = "92aa85c19c3d0dcfd531f42b75743559efd4f80919942a9acce5f5e15d323c4a"
FIXTURE_SEMANTIC_SHA256 = "e5f5da08e77e057960fe9ab987b3400e5557a017ae62fcdaa8d4e376042d7f76"
FIXTURE_UNIT_SHA256 = "bc190f7c3214d816d04334968cc2f651766c8b3753c229efdd6bb39c146f7f72"
FIXTURE_UNIT = VENDOR / "fixtures" / "ada" / "wire_shape.ads"
FIXTURE_PROJECT_SHA256 = "2014d1478875f6f47f37ae56a37f35d98becefdbb40a1dbd385106b50a3c0fb3"
FIXTURE_PROJECT = VENDOR / "fixtures" / "fixtures.gpr"
MAXIMUM_ADA_NATURAL = 2_147_483_647
MAXIMUM_ADA_SELECTED_NAME_LENGTH = 48
MAXIMUM_ADA_STRING_LITERAL_LENGTH = 58


def configure_root(root: Path) -> None:
    global ROOT, VENDOR, CHECKER, TYPE_IR_SCHEMA
    global FIXTURE_UNIT, FIXTURE_PROJECT
    ROOT = root.resolve()
    VENDOR = ROOT / "vendor" / "type_ir"
    CHECKER = VENDOR / "scripts" / "check_fixtures.py"
    TYPE_IR_SCHEMA = VENDOR / "schema" / "type-ir-v1.schema.json"
    FIXTURE_UNIT = VENDOR / "fixtures" / "ada" / "wire_shape.ads"
    FIXTURE_PROJECT = VENDOR / "fixtures" / "fixtures.gpr"


class GenerationError(ValueError):
    pass


class CheckedOverlay(NamedTuple):
    document: dict[str, Any]
    raw: bytes
    sha256: str


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bytes_sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


@contextlib.contextmanager
def load_checker():
    checker_bytes = CHECKER.read_bytes()
    schema_bytes = TYPE_IR_SCHEMA.read_bytes()
    project_bytes = FIXTURE_PROJECT.read_bytes()
    unit_bytes = FIXTURE_UNIT.read_bytes()
    if bytes_sha256(checker_bytes) != CHECKER_SHA256:
        raise GenerationError("vendored Type IR checker digest mismatch")
    if bytes_sha256(schema_bytes) != SCHEMA_SHA256:
        raise GenerationError("vendored Type IR schema digest mismatch")
    if bytes_sha256(project_bytes) != FIXTURE_PROJECT_SHA256:
        raise GenerationError("vendored Type IR fixture project digest mismatch")
    if bytes_sha256(unit_bytes) != FIXTURE_UNIT_SHA256:
        raise GenerationError("vendored Type IR fixture unit digest mismatch")
    with tempfile.TemporaryDirectory(prefix="flyology-serde-type-ir-") as directory:
        root = Path(directory)
        checker = root / "scripts" / "check_fixtures.py"
        schema = root / "schema" / "type-ir-v1.schema.json"
        project = root / "fixtures" / "fixtures.gpr"
        unit = root / "fixtures" / "ada" / "wire_shape.ads"
        checker.parent.mkdir()
        schema.parent.mkdir()
        project.parent.mkdir()
        unit.parent.mkdir()
        checker.write_bytes(checker_bytes)
        schema.write_bytes(schema_bytes)
        project.write_bytes(project_bytes)
        unit.write_bytes(unit_bytes)
        name = "_flyology_serde_pinned_type_ir_checker"
        spec = importlib.util.spec_from_file_location(name, checker)
        if spec is None or spec.loader is None:
            raise GenerationError("cannot load vendored Type IR checker")
        module = importlib.util.module_from_spec(spec)
        prior_bytecode = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        sys.modules[name] = module
        try:
            spec.loader.exec_module(module)
            yield module
        finally:
            sys.modules.pop(name, None)
            sys.dont_write_bytecode = prior_bytecode


def load_type_ir(path: Path, profile: str):
    raw = path.read_bytes()
    with tempfile.TemporaryDirectory(prefix="flyology-serde-input-") as directory:
        materialized = Path(directory) / "document.json"
        materialized.write_bytes(raw)
        with load_checker() as checker:
            checked = checker.load_checked(materialized, profile)
        return checked


def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise GenerationError(f"duplicate overlay key: {key}")
        result[key] = value
    return result


def canonical_bytes(value: object) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("utf-8")


def reject_constant(value: str) -> None:
    raise GenerationError(f"nonfinite JSON number is not allowed: {value}")


def load_overlay(path: Path) -> CheckedOverlay:
    raw = path.read_bytes()
    try:
        value = json.loads(
            raw, object_pairs_hook=reject_duplicates, parse_constant=reject_constant
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GenerationError(f"invalid overlay JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise GenerationError("overlay root must be an object")
    if raw != canonical_bytes(value):
        raise GenerationError("overlay JSON is not canonical")
    expected = {
        "fixture_only", "output_unit", "overlay_version", "records", "serialization_limits",
        "type_ir_commit", "type_ir_semantic_fingerprint", "type_ir_source_sha256", "with_units",
    }
    if set(value) != expected:
        raise GenerationError("overlay keys do not match serde overlay v1")
    if value["overlay_version"] != 1 or value["type_ir_commit"] != TYPE_IR_COMMIT:
        raise GenerationError("unsupported overlay or Type IR version")
    if not isinstance(value["fixture_only"], bool):
        raise GenerationError("fixture_only must be Boolean")
    if not isinstance(value["records"], list) or not value["records"]:
        raise GenerationError("records must be a nonempty array")
    if not isinstance(value["with_units"], list):
        raise GenerationError("with_units must be an array")
    limits = value["serialization_limits"]
    limit_keys = {
        "maximum_byte_length", "maximum_container_items", "maximum_logical_events",
        "maximum_nesting_depth", "maximum_text_length",
    }
    if not isinstance(limits, dict) or set(limits) != limit_keys:
        raise GenerationError("serialization_limits keys do not match v1")
    for key, limit in limits.items():
        if (
            not isinstance(limit, int)
            or isinstance(limit, bool)
            or limit < 0
            or limit > MAXIMUM_ADA_NATURAL
        ):
            raise GenerationError(f"serialization_limits/{key} is invalid")
    if limits["maximum_nesting_depth"] > 256:
        raise GenerationError("maximum_nesting_depth exceeds the runtime stack bound")
    validate_selected_name(value["output_unit"], "output_unit")
    for digest_name in ("type_ir_semantic_fingerprint", "type_ir_source_sha256"):
        digest = value[digest_name]
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise GenerationError(f"{digest_name} is not a SHA-256 digest")
    folded_units: set[str] = set()
    for unit in value["with_units"]:
        validate_selected_name(unit, "with_units")
        if unit.casefold() in folded_units:
            raise GenerationError("duplicate with unit")
        folded_units.add(unit.casefold())
    return CheckedOverlay(value, raw, bytes_sha256(raw))


def validate_selected_name(value: object, path: str) -> str:
    if not isinstance(value, str) or not SELECTED_NAME.fullmatch(value):
        raise GenerationError(f"{path} is not an Ada selected name")
    if any(segment.endswith("_") or "__" in segment for segment in value.split(".")):
        raise GenerationError(f"{path} is not an Ada selected name")
    if any(segment.casefold() in RESERVED for segment in value.split(".")):
        raise GenerationError(f"{path} contains an Ada reserved word")
    if len(value) > MAXIMUM_ADA_SELECTED_NAME_LENGTH:
        raise GenerationError(f"{path} exceeds the v1 Ada source line bound")
    return value


def validate_logical_name(value: object, path: str) -> str:
    if not isinstance(value, str) or not value:
        raise GenerationError(f"{path} must be nonempty text")
    if len(value) > 64:
        raise GenerationError(f"{path} exceeds the v1 64-byte name bound")
    if any(ord(character) < 32 or ord(character) > 126 for character in value):
        raise GenerationError(f"{path} is outside the v1 printable-ASCII repertoire")
    if len(ada_string_literal(value)) > MAXIMUM_ADA_STRING_LITERAL_LENGTH:
        raise GenerationError(f"{path} exceeds the v1 escaped Ada literal line bound")
    return value


def ada_string_literal(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def selected_name_matches_canonical(selected_name: str, canonical_name: str) -> bool:
    selected = selected_name.casefold()
    canonical = canonical_name.casefold()
    return selected == canonical or (canonical == "standard.boolean" and selected == "boolean")


def freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: freeze(child) for key, child in value.items()})
    if isinstance(value, list):
        return tuple(freeze(child) for child in value)
    return value


def known_boolean(fact: Mapping[str, Any], path: str) -> bool:
    if fact.get("status") != "known":
        raise GenerationError(f"{path} is not Known")
    value = fact.get("value")
    if not isinstance(value, Mapping) or value.get("kind") != "boolean":
        raise GenerationError(f"{path} is not a Known Boolean")
    return bool(value.get("value"))


def require_safe_declaration(declaration: Mapping[str, Any]) -> None:
    stable_id = str(declaration["stable_id"])
    if declaration["view"] != "public" or declaration["declaration_form"] != "type":
        raise GenerationError(f"{stable_id}: only direct public type declarations are supported")
    if declaration["references"] or declaration["related_view_ids"]:
        raise GenerationError(f"{stable_id}: referenced, derived, or alternate views require an adapter")
    if not known_boolean(
        declaration["view_access"]["representation_available"],
        f"{stable_id}/representation_available",
    ):
        raise GenerationError(f"{stable_id}: representation is not available to the consumer")
    facts = declaration["facts"]
    if not known_boolean(facts["definite"], f"{stable_id}/definite"):
        raise GenerationError(f"{stable_id}: indefinite type requires an adapter")
    forbidden = (
        "limited", "controlled", "contains_controlled", "contains_access", "tagged",
        "class_wide", "abstract", "task", "protected",
    )
    for name in forbidden:
        if known_boolean(facts[name], f"{stable_id}/{name}"):
            raise GenerationError(f"{stable_id}: {name} type requires an adapter")


def decimal_fact(fact: Mapping[str, Any], path: str) -> int:
    if fact.get("status") != "known":
        raise GenerationError(f"{path} is not Known")
    value = fact.get("value")
    if not isinstance(value, Mapping) or value.get("kind") != "decimal_integer":
        raise GenerationError(f"{path} is not an exact integer")
    return int(str(value["value"]))


def scalar_kind(declaration: Mapping[str, Any]) -> str:
    require_safe_declaration(declaration)
    stable_id = str(declaration["stable_id"])
    shape = declaration["shape"]
    kind = shape["kind"]
    if kind == "boolean_scalar":
        if (
            stable_id != "decl:standard.boolean#public"
            or str(declaration["canonical_name"]).casefold() != "standard.boolean"
            or known_boolean(shape["predicate"], f"{stable_id}/predicate")
            or shape["range"]["kind"] != "scalar_range"
            or not known_boolean(shape["range"]["staticness"], f"{stable_id}/staticness")
            or known_boolean(shape["range"]["predicate"], f"{stable_id}/range_predicate")
            or known_boolean(shape["range"]["static_low"], f"{stable_id}/low")
            or not known_boolean(shape["range"]["static_high"], f"{stable_id}/high")
        ):
            raise GenerationError(f"{stable_id}: only exact Standard.Boolean is supported")
        return "boolean"
    if kind not in {"signed_scalar", "modular_scalar"}:
        raise GenerationError(f"{stable_id}: unsupported reachable scalar shape {kind}")
    if known_boolean(shape["predicate"], f"{stable_id}/predicate"):
        raise GenerationError(f"{stable_id}: predicates require an adapter")
    if shape["range"]["kind"] != "scalar_range":
        raise GenerationError(f"{stable_id}: scalar range is malformed")
    if not known_boolean(shape["range"]["staticness"], f"{stable_id}/staticness"):
        raise GenerationError(f"{stable_id}: dynamic scalar range requires an adapter")
    if known_boolean(shape["range"]["predicate"], f"{stable_id}/range_predicate"):
        raise GenerationError(f"{stable_id}: range predicate requires an adapter")
    low = decimal_fact(shape["range"]["static_low"], f"{stable_id}/low")
    high = decimal_fact(shape["range"]["static_high"], f"{stable_id}/high")
    if kind == "signed_scalar" and not (-(2**63) <= low <= high <= 2**63 - 1):
        raise GenerationError(f"{stable_id}: signed range exceeds Integer_64")
    if kind == "modular_scalar":
        modulus = decimal_fact(shape["modulus"], f"{stable_id}/modulus")
        if low != 0 or high != modulus - 1 or modulus > 2**64:
            raise GenerationError(f"{stable_id}: modular range exceeds Unsigned_64")
    return "signed" if kind == "signed_scalar" else "modular"


def lower(
    document: Mapping[str, Any],
    overlay: Mapping[str, Any],
    *,
    fixture_only: bool,
) -> Mapping[str, Any]:
    if document["generic_actuals"]:
        raise GenerationError("v1 rejects every document containing generic actuals")
    if not fixture_only:
        raise GenerationError(
            "strict generation awaits a mandatory record-predicate structural fact"
        )
    context = document["context"]["accessibility_context"]
    if str(context["consumer_unit"]).casefold() != overlay["output_unit"].casefold():
        raise GenerationError("output_unit does not match Type IR accessibility context")
    selected_units = document["context"]["effective_project"]["selected_units"]
    available_units: dict[str, str] = {}
    for selected_unit in selected_units:
        unit_name = validate_selected_name(
            selected_unit["unit_name"], "context/effective_project/selected_units"
        )
        folded = unit_name.casefold()
        if folded in available_units:
            raise GenerationError("Type IR project closure contains a duplicate unit name")
        available_units[folded] = unit_name

    needed_units: set[str] = set()

    def require_context_for(selected_name: str, path: str) -> None:
        folded_name = selected_name.casefold()
        matches = [
            canonical
            for folded, canonical in available_units.items()
            if folded_name == folded or folded_name.startswith(folded + ".")
        ]
        if not matches:
            if folded_name == "boolean":
                return
            raise GenerationError(f"{path} is not nameable from the attested project closure")
        needed_units.add(max(matches, key=len))

    declarations = {item["stable_id"]: item for item in document["declarations"]}
    components = {item["stable_id"]: item for item in document["components"]}
    lowered_records: list[dict[str, Any]] = []
    seen_roots: set[str] = set()
    for index, record in enumerate(overlay["records"]):
        expected = {"ada_type", "declaration_id", "fields", "logical_type_name"}
        if not isinstance(record, dict) or set(record) != expected:
            raise GenerationError(f"records/{index}: keys do not match v1")
        root_id = str(record["declaration_id"])
        if root_id in seen_roots:
            raise GenerationError(f"records/{index}: duplicate root")
        seen_roots.add(root_id)
        declaration = declarations.get(root_id)
        if declaration is None:
            raise GenerationError(f"records/{index}: dangling declaration_id")
        require_safe_declaration(declaration)
        if declaration["shape"]["kind"] != "record":
            raise GenerationError(f"{root_id}: selected root is not a record")
        if declaration["shape"] != {"kind": "record", "constraint": {"kind": "none"}}:
            raise GenerationError(f"{root_id}: constrained record roots require an adapter")
        if not known_boolean(
            declaration["view_access"]["consumer_can_name_components"],
            f"{root_id}/consumer_can_name_components",
        ):
            raise GenerationError(f"{root_id}: components are not visible")
        if any(item["owner_id"] == root_id for item in document["discriminants"]):
            raise GenerationError(f"{root_id}: discriminated records require an adapter")
        if any(item["owner_id"] == root_id for item in document["variants"]):
            raise GenerationError(f"{root_id}: variants require an adapter")
        root_ada_type = validate_selected_name(record["ada_type"], f"records/{index}/ada_type")
        if not selected_name_matches_canonical(root_ada_type, str(declaration["canonical_name"])):
            raise GenerationError(f"{root_id}: Ada root binding does not match canonical identity")
        require_context_for(root_ada_type, f"records/{index}/ada_type")
        logical_type_name = validate_logical_name(
            record["logical_type_name"], f"records/{index}/logical_type_name"
        )
        owned = sorted(
            (item for item in components.values() if item["owner_id"] == root_id),
            key=lambda item: item["declaration_order"],
        )
        bindings = record["fields"]
        if not isinstance(bindings, list) or len(bindings) != len(owned) or not owned:
            raise GenerationError(f"{root_id}: field bindings are not complete")
        for binding_index, binding in enumerate(bindings):
            if not isinstance(binding, dict) or set(binding) != {
                "ada_component", "ada_type", "component_id", "presentation_name"
            }:
                raise GenerationError(
                    f"records/{index}/fields/{binding_index}: keys do not match v1"
                )
        by_id = {item["component_id"]: item for item in bindings}
        if len(by_id) != len(bindings):
            raise GenerationError(f"{root_id}: duplicate component binding")
        fields: list[dict[str, str]] = []
        presentation_names: set[str] = set()
        for position, component in enumerate(owned):
            binding = by_id.get(component["stable_id"])
            if not isinstance(binding, dict):
                raise GenerationError(f"{root_id}: incomplete component binding")
            if component["default"]["present"]:
                raise GenerationError(f"{component['stable_id']}: defaults are not supported")
            if component["variant_path"]:
                raise GenerationError(f"{component['stable_id']}: variant path is not supported")
            if known_boolean(component["aliased"], f"{component['stable_id']}/aliased"):
                raise GenerationError(f"{component['stable_id']}: aliased component requires an adapter")
            if known_boolean(component["constant"], f"{component['stable_id']}/constant"):
                raise GenerationError(f"{component['stable_id']}: constant component cannot be built")
            if component["type"]["constraint"] != {"kind": "none"}:
                raise GenerationError(f"{component['stable_id']}: use-site constraints require an adapter")
            child = declarations.get(component["type"]["declaration_id"])
            if child is None:
                raise GenerationError(f"{component['stable_id']}: dangling component type")
            kind = scalar_kind(child)
            ada_component = validate_selected_name(
                binding["ada_component"], f"records/{index}/fields/{position}"
            )
            if "." in ada_component or ada_component.casefold() != str(component["name"]).casefold():
                raise GenerationError(
                    f"{component['stable_id']}: Ada component binding does not match its declaration"
                )
            ada_type = validate_selected_name(
                binding["ada_type"], f"records/{index}/fields/{position}/ada_type"
            )
            if not selected_name_matches_canonical(ada_type, str(child["canonical_name"])):
                raise GenerationError(
                    f"{component['stable_id']}: Ada type binding does not match canonical identity"
                )
            require_context_for(ada_type, f"records/{index}/fields/{position}/ada_type")
            presentation_name = validate_logical_name(
                binding["presentation_name"],
                f"records/{index}/fields/{position}/presentation_name",
            )
            if presentation_name in presentation_names:
                raise GenerationError(f"{root_id}: duplicate presentation name")
            presentation_names.add(presentation_name)
            fields.append(
                {
                    "ada_component": ada_component,
                    "ada_type": ada_type,
                    "kind": kind,
                    "name": presentation_name,
                    "type_id": str(child["stable_id"]),
                    "adapter_unit": (
                        f"Field_{position + 1}_Adapter"
                        if kind in {"signed", "modular"}
                        else None
                    ),
                }
            )
        lowered_records.append(
            {
                "ada_type": record["ada_type"],
                "fields": fields,
                "logical_type_name": logical_type_name,
                "stable_id": root_id,
            }
        )
    expected_with_units = sorted(needed_units, key=str.casefold)
    overlay_with_units = list(overlay["with_units"])
    if (
        [unit.casefold() for unit in overlay_with_units]
        != [unit.casefold() for unit in expected_with_units]
        or not expected_with_units
    ):
        raise GenerationError(
            "with_units must exactly equal the required attested project context"
        )
    return freeze({
        "limits": dict(overlay["serialization_limits"]),
        "output_unit": overlay["output_unit"],
        "records": lowered_records,
        "with_units": overlay_with_units,
    })


def ada_filename(unit: str, extension: str) -> str:
    return unit.casefold().replace(".", "-") + extension


def render(
    model: Mapping[str, Any],
    attestation: Mapping[str, str],
    fixture_only: bool,
) -> tuple[str, str]:
    if len(model["records"]) != 1:
        raise GenerationError("v1 emitter accepts exactly one record")
    record = model["records"][0]
    limits = model["limits"]
    unit = model["output_unit"]
    marker = "--  FLYOLOGY_SERDE_TEST_FIXTURE_ONLY\n" if fixture_only else ""
    header = (
        marker
        + f"--  Generated by {GENERATOR_VERSION}; do not edit.\n"
        + f"--  Generator source SHA-256: {attestation['generator_source_sha256']}\n"
        + f"--  Type IR commit: {TYPE_IR_COMMIT}\n"
        + f"--  Type IR source SHA-256: {attestation['source_sha256']}\n"
        + f"--  Type IR semantic SHA-256: {attestation['semantic_fingerprint']}\n"
        + f"--  Overlay SHA-256: {attestation['overlay_sha256']}\n"
    )
    withs = "\n".join(f"with {name};" for name in model["with_units"])
    spec = f"""{header}{withs}
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

package {unit} is
   type Builder is limited private;

   procedure Initialize
     (Target : in out Builder;
      Value  : {record['ada_type']};
      Error  : in out Flyology_Serde.Errors.Error_Info);
   function Has_Value (Target : Builder) return Boolean;
   function Value (Target : Builder) return {record['ada_type']}
   with Pre => Has_Value (Target);

   procedure Serialize
     (Item  : {record['ada_type']};
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info);

   procedure Deserialize
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Builder;
      Error  : in out Flyology_Serde.Errors.Error_Info);

private
   type Builder is limited record
      Published : {record['ada_type']};
      Candidate : {record['ada_type']};
      Initialized : Boolean := False;
      Active      : Boolean := False;
      Root_Started : Boolean := False;
   end record;
end {unit};
"""
    instantiations = []
    for field in record["fields"]:
        adapter = field.get("adapter_unit")
        if adapter:
            generic = "Signed_Integers" if field["kind"] == "signed" else "Unsigned_Integers"
            instantiations.append(
                f"   package {adapter} is new Flyology_Serde.Adapters.{generic}\n"
                f"     ({field['ada_type']});"
            )
    serialize_lines = []
    decode_branches = []
    missing_checks = []
    for position, field in enumerate(record["fields"], start=1):
        component = field["ada_component"]
        adapter = field.get("adapter_unit")
        name = field["name"]
        literal = ada_string_literal(name)
        serialize_lines.append(f"      Into.Put_Field ({literal}, Error);")
        if field["kind"] == "boolean":
            serialize_lines.append(f"      Into.Put_Boolean (Item.{component}, Error);")
            read = f"From.Read_Boolean (Target.Candidate.{component}, Error);"
        elif field["kind"] == "signed":
            serialize_lines.append(
                f"      {adapter}.Serialize_Value (Item.{component}, Into, Error);"
            )
            read = (
                f"{adapter}.Deserialize_Candidate "
                f"(From, Target.Candidate.{component}, Error);"
            )
        else:
            serialize_lines.append(
                f"      {adapter}.Serialize_Value (Item.{component}, Into, Error);"
            )
            read = (
                f"{adapter}.Deserialize_Candidate "
                f"(From, Target.Candidate.{component}, Error);"
            )
        decode_branches.append(
            f"         {'if' if position == 1 else 'elsif'} Name (1 .. Name_Last) = {literal} then\n"
            f"               if Seen ({position}) then\n"
            f"                  Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Duplicate_Field);\n"
            f"               else\n"
            f"                  Seen ({position}) := True;\n"
            f"                  {read}\n"
            f"               end if;"
        )
        missing_checks.append(
            f"      if Error.Code = Flyology_Serde.Errors.No_Error and then not Seen ({position}) then\n"
            f"         Flyology_Serde.Errors.Push_Field (Error, {literal});\n"
            f"         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Missing_Field);\n"
            f"      end if;"
        )
    instantiation_text = "\n".join(instantiations)
    serialization_text = "\n".join(serialize_lines)
    decode_text = "\n".join(decode_branches)
    missing_text = "\n".join(missing_checks)
    logical_type_literal = ada_string_literal(record["logical_type_name"])
    body = f"""{header}with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Adapters.Unsigned_Integers;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization_Adapters;

package body {unit} is
   use type Flyology_Serde.Errors.Error_Code;

{instantiation_text}

   Default_Policy : constant Flyology_Serde.Policies.Decode_Policy := (others => <>);

   Serialization_Limits : constant Flyology_Serde.Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => {limits['maximum_nesting_depth']},
      Maximum_Container_Items => {limits['maximum_container_items']},
      Maximum_Text_Length     => {limits['maximum_text_length']},
      Maximum_Byte_Length     => {limits['maximum_byte_length']},
      Maximum_Logical_Events  => {limits['maximum_logical_events']});

   procedure Serialize_Value
     (Item  : {record['ada_type']};
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info) is
   begin
      Into.Begin_Record ({logical_type_literal}, {len(record['fields'])}, Error);
{serialization_text}
      Into.End_Record (Error);
   end Serialize_Value;

   procedure Begin_Candidate
     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is
   begin
      if Target.Active then
         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);
      else
         Target.Active := True;
         Target.Root_Started := True;
      end if;
   end Begin_Candidate;

   procedure Deserialize_Value
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Builder;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Flyology_Serde.Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
      Length    : Flyology_Serde.Data_Model.Length_Information;
      Available : Boolean := False;
      Name      : String (1 .. 64);
      Name_Last : Natural := 0;
      Seen      : array (Positive range 1 .. {len(record['fields'])}) of Boolean := [others => False];
   begin
      From.Begin_Record ({logical_type_literal}, Length, Error);
      while Error.Code = Flyology_Serde.Errors.No_Error loop
         From.Next_Field (Name, Name_Last, Available, Error);
         exit when Error.Code /= Flyology_Serde.Errors.No_Error or else not Available;
         Flyology_Serde.Errors.Push_Field (Error, Name (1 .. Name_Last));
{decode_text}
         else
            Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Unknown_Field);
         end if;
         exit when Error.Code /= Flyology_Serde.Errors.No_Error;
         Flyology_Serde.Errors.Pop (Error);
      end loop;
      if Error.Code = Flyology_Serde.Errors.No_Error then
         From.End_Record (Error);
      end if;
{missing_text}
   end Deserialize_Value;

   procedure Commit_Candidate
     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is
   begin
      if not Target.Active or else not Target.Root_Started then
         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);
      else
         Target.Published := Target.Candidate;
         Target.Initialized := True;
         Target.Active := False;
         Target.Root_Started := False;
      end if;
   end Commit_Candidate;

   procedure Rollback_Candidate (Target : in out Builder) is
   begin
      if Target.Root_Started then
         Target.Active := False;
         Target.Root_Started := False;
      end if;
   exception
      when others =>
         null;
   end Rollback_Candidate;

   package Serialization_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => {record['ada_type']},
      Limits           => Serialization_Limits,
      Serialize_Value => Serialize_Value);

   package Deserialization_Root is new Flyology_Serde.Deserialization_Adapters
     (Builder_Type       => Builder,
      Policy             => Default_Policy,
      Begin_Candidate    => Begin_Candidate,
      Deserialize_Value  => Deserialize_Value,
      Commit_Candidate   => Commit_Candidate,
      Rollback_Candidate => Rollback_Candidate);

   procedure Initialize
     (Target : in out Builder;
      Value  : {record['ada_type']};
      Error  : in out Flyology_Serde.Errors.Error_Info) is
   begin
      if Error.Code /= Flyology_Serde.Errors.No_Error then
         return;
      elsif Target.Active then
         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);
      else
         Target.Published := Value;
         Target.Candidate := Value;
         Target.Initialized := True;
         Target.Root_Started := False;
      end if;
   end Initialize;

   function Has_Value (Target : Builder) return Boolean
   is (Target.Initialized and then not Target.Active);

   function Value (Target : Builder) return {record['ada_type']}
   is (Target.Published);

   procedure Serialize
     (Item  : {record['ada_type']};
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info) is
   begin
      Serialization_Root.Serialize (Item, Into, Error);
   end Serialize;

   procedure Deserialize
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Builder;
      Error  : in out Flyology_Serde.Errors.Error_Info) is
   begin
      Deserialization_Root.Deserialize (From, Target, Error);
   end Deserialize;
end {unit};
"""
    return spec, body


def publish(output: Path, files: dict[str, bytes], manifest: dict[str, Any]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{output.name}-", dir=output.parent))
    claimed = False
    try:
        for name, content in files.items():
            (staging / name).write_bytes(content)
        manifest["files"] = {
            name: hashlib.sha256(content).hexdigest() for name, content in sorted(files.items())
        }
        (staging / "serde-generation.json").write_bytes(canonical_bytes(manifest))
        try:
            output.mkdir()
            claimed = True
        except FileExistsError as exc:
            raise GenerationError(
                "output directory already exists; refusing to overwrite it"
            ) from exc
        for name in sorted(files):
            os.link(staging / name, output / name)
        os.link(staging / "serde-generation.json", output / "serde-generation.json")
    except Exception:
        if claimed and output.exists():
            for path in output.iterdir():
                path.unlink()
            output.rmdir()
        raise
    finally:
        for path in staging.iterdir() if staging.exists() else ():
            path.unlink()
        if staging.exists():
            staging.rmdir()


def main(*, generator_source_sha256: str) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--type-ir", type=Path, required=True)
    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test-fixture-shape", action="store_true")
    args = parser.parse_args()
    try:
        checked_overlay = load_overlay(args.overlay)
        overlay = checked_overlay.document
        profile = "fixture_shape" if args.test_fixture_shape else "strict"
        if overlay["fixture_only"] != args.test_fixture_shape:
            raise GenerationError("fixture_only must exactly match --test-fixture-shape")
        checked = load_type_ir(args.type_ir, profile)
        if checked.semantic_fingerprint != overlay["type_ir_semantic_fingerprint"]:
            raise GenerationError("overlay semantic fingerprint is stale")
        if checked.source_sha256 != overlay["type_ir_source_sha256"]:
            raise GenerationError("overlay Type IR source digest is stale")
        if args.test_fixture_shape:
            if (
                checked.source_sha256 != FIXTURE_SOURCE_SHA256
                or checked.semantic_fingerprint != FIXTURE_SEMANTIC_SHA256
            ):
                raise GenerationError("fixture source, semantic, or selected-unit digest mismatch")
        immutable_document = freeze(checked.document)
        model = lower(
            immutable_document,
            overlay,
            fixture_only=args.test_fixture_shape,
        )
        attestation = {
            "generator_source_sha256": generator_source_sha256,
            "semantic_fingerprint": checked.semantic_fingerprint,
            "source_sha256": checked.source_sha256,
            "overlay_sha256": checked_overlay.sha256,
        }
        spec, body = render(model, attestation, args.test_fixture_shape)
        unit = model["output_unit"]
        files = {
            ada_filename(unit, ".ads"): spec.encode("utf-8"),
            ada_filename(unit, ".adb"): body.encode("utf-8"),
        }
        manifest = {
            "fixture_only": args.test_fixture_shape,
            "generator_source_sha256": attestation["generator_source_sha256"],
            "generator_version": GENERATOR_VERSION,
            "overlay_sha256": attestation["overlay_sha256"],
            "type_ir_checker_sha256": CHECKER_SHA256,
            "type_ir_commit": TYPE_IR_COMMIT,
            "type_ir_schema_sha256": SCHEMA_SHA256,
            "type_ir_semantic_fingerprint": checked.semantic_fingerprint,
            "type_ir_source_sha256": checked.source_sha256,
            "type_ir_fixture_unit_sha256": FIXTURE_UNIT_SHA256 if args.test_fixture_shape else "",
        }
        publish(args.output, files, manifest)
    except Exception as exc:
        print(f"flyology-serde-generator: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit("use generate.py so executed implementation bytes are attested")
