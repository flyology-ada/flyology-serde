import collections
import hashlib
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PUBLIC_SPEC = ROOT / "src" / "flyology_serde-deserializers-json.ads"
PUBLIC_BODY = ROOT / "src" / "flyology_serde-deserializers-json.adb"

EXPECTED_VISIBLE_SHA256 = (
    "f85f6c62e426fc181ceca7565357401c30c538cddf914a18948f47bfc93f9fed"
)

EXPECTED_DELEGATIONS = collections.Counter(
    {
        "Abort_Document": 1,
        "Begin_Map": 1,
        "Begin_Optional": 1,
        "Begin_Record": 1,
        "Begin_Sequence": 1,
        "Begin_Variant": 1,
        "Capabilities": 1,
        "End_Map": 1,
        "End_Optional": 1,
        "End_Record": 1,
        "End_Sequence": 1,
        "End_Variant": 1,
        "Finish_Document": 1,
        "Input_Offset": 1,
        "Is_Complete": 1,
        "Next_Element": 1,
        "Next_Field": 1,
        "Next_Map_Entry": 1,
        "Peek_Kind": 1,
        "Read_Boolean": 1,
        "Read_Bytes": 1,
        "Read_Enumeration": 1,
        "Read_Float_64": 1,
        "Read_Null": 1,
        "Read_Signed": 1,
        "Read_Text": 1,
        "Read_Unsigned": 1,
        "Reinitialize": 2,
        "Skip_Value": 1,
    }
)


class JSONPublicCutoverTests(unittest.TestCase):
    def test_visible_public_declarations_are_frozen(self) -> None:
        source = PUBLIC_SPEC.read_text(encoding="utf-8")
        first = source.index("package Flyology_Serde.Deserializers.JSON is")
        last = source.index("\nprivate\n", first)
        visible = source[first:last].encode("utf-8")
        self.assertEqual(hashlib.sha256(visible).hexdigest(), EXPECTED_VISIBLE_SHA256)

    def test_facade_has_exact_closed_delegation_set(self) -> None:
        source = PUBLIC_BODY.read_text(encoding="utf-8")
        actual = collections.Counter(
            re.findall(r"JSON_Event_Readers\.([A-Za-z0-9_]+)", source)
        )
        self.assertEqual(actual, EXPECTED_DELEGATIONS)
        self.assertNotIn("exception", source.lower())
        self.assertEqual(
            source.count("Self.Implementation"), sum(EXPECTED_DELEGATIONS.values())
        )

    def test_only_current_event_reader_is_a_production_source(self) -> None:
        production_names = {path.name for path in (ROOT / "src").iterdir()}
        self.assertIn(
            "flyology_serde-deserializers-json_event_readers.ads", production_names
        )
        self.assertIn(
            "flyology_serde-deserializers-json_event_readers.adb", production_names
        )
        self.assertNotIn(
            "flyology_serde-deserializers-json-event_readers.ads", production_names
        )
        self.assertNotIn(
            "flyology_serde-deserializers-json-event_readers.adb", production_names
        )
        self.assertFalse(
            any("handwritten_oracle" in name.lower() for name in production_names)
        )


if __name__ == "__main__":
    unittest.main()
