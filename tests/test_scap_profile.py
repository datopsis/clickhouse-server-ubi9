import unittest
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
TAILORING = ROOT / "security" / "scap" / "datopsis-ubi9-micro-tailoring.xml"
RATIONALE = ROOT / "security" / "scap" / "RULE-RATIONALE.md"


class ScapProfileTests(unittest.TestCase):
    def test_profile_is_explicit_and_every_rule_is_documented(self) -> None:
        root = ET.parse(TAILORING).getroot()
        profile = next(element for element in root.iter() if element.tag.endswith("Profile"))
        self.assertNotIn("extends", profile.attrib)

        selections = [
            element.attrib["idref"]
            for element in profile
            if element.tag.endswith("select") and element.attrib.get("selected") == "true"
        ]
        self.assertEqual(len(selections), 36)
        self.assertEqual(len(selections), len(set(selections)))

        rationale = RATIONALE.read_text(encoding="utf-8")
        for rule_id in selections:
            short_id = rule_id.removeprefix("xccdf_org.ssgproject.content_rule_")
            with self.subTest(rule=short_id):
                self.assertIn(short_id, rationale)

    def test_profile_id_is_stable(self) -> None:
        root = ET.parse(TAILORING).getroot()
        profile = next(element for element in root.iter() if element.tag.endswith("Profile"))
        self.assertEqual(
            profile.attrib["id"], "xccdf_org.datopsis_profile_ubi9_micro_container"
        )


if __name__ == "__main__":
    unittest.main()
