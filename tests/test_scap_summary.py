import unittest
from collections import Counter
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "scap-summary.py"
SPEC = spec_from_file_location("scap_summary", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
SCAP_SUMMARY = module_from_spec(SPEC)
SPEC.loader.exec_module(SCAP_SUMMARY)


class ScapSummaryTests(unittest.TestCase):
    def inventory(self, xml: str) -> list[dict[str, str]]:
        return SCAP_SUMMARY.inventory_root(ET.fromstring(xml))

    def test_inventories_and_sorts_results(self) -> None:
        rules = self.inventory(
            """<Benchmark xmlns="http://checklists.nist.gov/xccdf/1.2">
            <TestResult>
              <rule-result idref="rule_b"><result>fail</result></rule-result>
              <rule-result idref="rule_a"><result>pass</result></rule-result>
              <rule-result idref="rule_c"><result>notapplicable</result></rule-result>
            </TestResult></Benchmark>"""
        )
        self.assertEqual(
            Counter(rule["result"] for rule in rules),
            {"fail": 1, "notapplicable": 1, "pass": 1},
        )
        self.assertEqual([rule["id"] for rule in rules], ["rule_a", "rule_b", "rule_c"])

    def test_errors_make_discovery_operationally_fail(self) -> None:
        self.assertTrue(SCAP_SUMMARY.has_operational_errors(Counter({"error": 1})))
        self.assertTrue(SCAP_SUMMARY.has_operational_errors(Counter({"unknown": 1})))
        self.assertFalse(SCAP_SUMMARY.has_operational_errors(Counter({"fail": 3})))

    def test_empty_result_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "no rule-result"):
            self.inventory("<Benchmark/>")


if __name__ == "__main__":
    unittest.main()
