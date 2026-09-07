#!/usr/bin/env python3
"""Create a deterministic inventory from an OpenSCAP XCCDF result file."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--architecture", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--mode", default="discovery-report-only")
    parser.add_argument("--target-image", required=True)
    parser.add_argument("--target-image-id", required=True)
    parser.add_argument("--scanner-image", required=True)
    parser.add_argument("--scanner-image-id", required=True)
    parser.add_argument("--datastream-sha256", required=True)
    parser.add_argument("--tailoring-sha256")
    parser.add_argument("--tailoring-file", type=Path)
    return parser.parse_args()


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def inventory_root(root: ET.Element) -> list[dict[str, str]]:
    rules: list[dict[str, str]] = []
    for element in root.iter():
        if local_name(element.tag) != "rule-result":
            continue
        result = next(
            (
                (child.text or "").strip()
                for child in element
                if local_name(child.tag) == "result"
            ),
            "missing",
        )
        rules.append({"id": element.attrib.get("idref", ""), "result": result})
    if not rules:
        raise ValueError("XCCDF results contain no rule-result elements")
    return sorted(rules, key=lambda item: item["id"])


def inventory(path: Path) -> list[dict[str, str]]:
    return inventory_root(ET.parse(path).getroot())


def tailoring_selections(path: Path) -> set[str]:
    root = ET.parse(path).getroot()
    selections = {
        element.attrib["idref"]
        for element in root.iter()
        if local_name(element.tag) == "select"
        and element.attrib.get("selected") == "true"
    }
    if not selections:
        raise ValueError("tailoring contains no selected rules")
    return selections


def has_operational_errors(counts: Counter[str]) -> bool:
    return bool(counts["error"] or counts["unknown"] or counts["missing"])


def main() -> int:
    args = parse_args()
    try:
        rules = inventory(args.results)
        if args.tailoring_file:
            expected_rules = tailoring_selections(args.tailoring_file)
            evaluated_rules = {
                rule["id"] for rule in rules if rule["result"] != "notselected"
            }
            if evaluated_rules != expected_rules:
                missing = sorted(expected_rules - evaluated_rules)
                unexpected = sorted(evaluated_rules - expected_rules)
                raise ValueError(
                    "tailored evaluation mismatch: "
                    f"missing={missing}, unexpected={unexpected}"
                )
    except (ET.ParseError, OSError, ValueError) as error:
        print(f"Unable to inventory SCAP results: {error}", file=sys.stderr)
        return 1

    counts = Counter(rule["result"] for rule in rules)
    document = {
        "schema_version": 1,
        "mode": args.mode,
        "architecture": args.architecture,
        "profile": args.profile,
        "target": {"reference": args.target_image, "image_id": args.target_image_id},
        "scanner": {
            "reference": args.scanner_image,
            "image_id": args.scanner_image_id,
        },
        "datastream_sha256": args.datastream_sha256,
        "counts": dict(sorted(counts.items())),
        "rules": rules,
    }
    if args.tailoring_sha256:
        document["tailoring_sha256"] = args.tailoring_sha256
    args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    print("SCAP result counts: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    if has_operational_errors(counts):
        print("SCAP produced an error, unknown, or missing result", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
