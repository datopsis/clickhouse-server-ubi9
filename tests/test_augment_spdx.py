import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "augment-spdx.py"
SPEC = importlib.util.spec_from_file_location("augment_spdx", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def base_document():
    return {
        "spdxVersion": "SPDX-2.3",
        "creationInfo": {"creators": ["Tool: syft"]},
        "packages": [
            {
                "name": "example-image",
                "SPDXID": "SPDXRef-Container",
                "primaryPackagePurpose": "CONTAINER",
            }
        ],
        "relationships": [],
    }


class AugmentSpdxTests(unittest.TestCase):
    def test_adds_clickhouse_packages_and_relationships(self):
        result = MODULE.augment(base_document(), "26.8.2.7", "stable")

        packages = {package["name"]: package for package in result["packages"]}
        for name in MODULE.CLICKHOUSE_PACKAGES:
            self.assertEqual(packages[name]["versionInfo"], "26.8.2.7")
            self.assertEqual(packages[name]["licenseDeclared"], "Apache-2.0")
            self.assertEqual(
                packages[name]["downloadLocation"],
                "https://packages.clickhouse.com/tgz/stable/",
            )

        cpes = packages["clickhouse-common-static"]["externalRefs"]
        self.assertTrue(any(ref["referenceType"] == "cpe23Type" for ref in cpes))
        self.assertEqual(len(result["relationships"]), 3)
        self.assertIn(
            "Tool: datopsis-spdx-augment", result["creationInfo"]["creators"]
        )

    def test_rejects_duplicate_clickhouse_package(self):
        document = base_document()
        document["packages"].append({"name": "clickhouse-client"})

        with self.assertRaisesRegex(ValueError, "duplicate"):
            MODULE.augment(document, "26.8.2.7", "stable")

    def test_reads_pinned_build_args(self):
        self.assertEqual(
            MODULE.read_clickhouse_build_args(
                Path(__file__).parents[1] / "Containerfile"
            ),
            ("26.8.2.7", "stable"),
        )


if __name__ == "__main__":
    unittest.main()
