#!/usr/bin/env python3
"""Add ClickHouse TGZ components that Syft cannot infer from the image filesystem."""

from __future__ import annotations

import argparse
import json
import re
import tempfile
from pathlib import Path
from typing import Any


CLICKHOUSE_PACKAGES = (
    "clickhouse-common-static",
    "clickhouse-server",
    "clickhouse-client",
)
BUILD_ARG_PATTERN = re.compile(
    r'^ARG (?P<name>CLICKHOUSE_(?:VERSION|CHANNEL))="(?P<value>[^"]+)"$',
    re.MULTILINE,
)


def read_clickhouse_build_args(containerfile: Path) -> tuple[str, str]:
    values: dict[str, set[str]] = {}
    for match in BUILD_ARG_PATTERN.finditer(containerfile.read_text(encoding="utf-8")):
        values.setdefault(match.group("name"), set()).add(match.group("value"))

    required = ("CLICKHOUSE_VERSION", "CLICKHOUSE_CHANNEL")
    missing = [name for name in required if name not in values]
    if missing:
        raise ValueError(f"{', '.join(missing)} is missing from {containerfile}")
    inconsistent = [name for name in required if len(values[name]) != 1]
    if inconsistent:
        raise ValueError(f"{', '.join(inconsistent)} is inconsistent in {containerfile}")
    return values["CLICKHOUSE_VERSION"].pop(), values["CLICKHOUSE_CHANNEL"].pop()


def augment(document: dict[str, Any], version: str, channel: str) -> dict[str, Any]:
    if document.get("spdxVersion") != "SPDX-2.3":
        raise ValueError("expected an SPDX 2.3 document")

    packages = document.get("packages")
    relationships = document.get("relationships")
    creation_info = document.get("creationInfo")
    if not isinstance(packages, list) or not isinstance(relationships, list):
        raise ValueError("SPDX document must contain package and relationship lists")
    if not isinstance(creation_info, dict):
        raise ValueError("SPDX document must contain creationInfo")

    package_names = {package.get("name") for package in packages}
    already_present = package_names.intersection(CLICKHOUSE_PACKAGES)
    if already_present:
        names = ", ".join(sorted(already_present))
        raise ValueError(f"refusing to duplicate existing ClickHouse packages: {names}")

    container_roots = [
        package
        for package in packages
        if package.get("primaryPackagePurpose") == "CONTAINER"
    ]
    if len(container_roots) != 1:
        raise ValueError("expected exactly one SPDX package with CONTAINER purpose")
    root_id = container_roots[0].get("SPDXID")
    if not isinstance(root_id, str) or not root_id.startswith("SPDXRef-"):
        raise ValueError("container package has no valid SPDXID")

    for name in CLICKHOUSE_PACKAGES:
        package_id = f"SPDXRef-Package-generic-{name}"
        external_refs = [
            {
                "referenceCategory": "PACKAGE-MANAGER",
                "referenceType": "purl",
                "referenceLocator": f"pkg:generic/clickhouse/{name}@{version}",
            }
        ]
        if name == "clickhouse-common-static":
            external_refs.append(
                {
                    "referenceCategory": "SECURITY",
                    "referenceType": "cpe23Type",
                    "referenceLocator": (
                        f"cpe:2.3:a:clickhouse:clickhouse:{version}:*:*:*:*:*:*:*"
                    ),
                }
            )

        packages.append(
            {
                "name": name,
                "SPDXID": package_id,
                "versionInfo": version,
                "supplier": "Organization: ClickHouse, Inc.",
                "downloadLocation": f"https://packages.clickhouse.com/tgz/{channel}/",
                "filesAnalyzed": False,
                "sourceInfo": (
                    "Declared from the pinned Containerfile build input; the upstream "
                    "TGZ and published SHA-512 are verified during the image build."
                ),
                "licenseConcluded": "Apache-2.0",
                "licenseDeclared": "Apache-2.0",
                "copyrightText": "NOASSERTION",
                "externalRefs": external_refs,
                "primaryPackagePurpose": "APPLICATION",
            }
        )
        relationships.append(
            {
                "spdxElementId": root_id,
                "relatedSpdxElement": package_id,
                "relationshipType": "CONTAINS",
            }
        )

    creators = creation_info.setdefault("creators", [])
    creator = "Tool: datopsis-spdx-augment"
    if creator not in creators:
        creators.append(creator)
    return document


def write_json_atomic(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as output:
        json.dump(document, output, indent=2)
        output.write("\n")
        temporary_path = Path(output.name)
    temporary_path.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--containerfile", default=Path("Containerfile"), type=Path)
    args = parser.parse_args()

    version, channel = read_clickhouse_build_args(args.containerfile)
    document = json.loads(args.input.read_text(encoding="utf-8"))
    write_json_atomic(args.output, augment(document, version, channel))


if __name__ == "__main__":
    main()
