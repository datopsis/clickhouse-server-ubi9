# Third-party software and terms

The root [Apache License 2.0](LICENSE) applies to Datopsis-authored packaging code and documentation in this repository. It does not replace the licenses or terms of software assembled into the container image.

## ClickHouse

The image uses unmodified official ClickHouse release archives for `clickhouse-common-static`, `clickhouse-server`, and `clickhouse-client`. ClickHouse open-source software is licensed under the [Apache License 2.0](https://github.com/ClickHouse/ClickHouse/blob/master/LICENSE). Copies supplied by the upstream archives remain in the image under `/usr/share/doc/clickhouse-*/LICENSE`.

ClickHouse is a trademark of ClickHouse, Inc. This repository is an independent packaging project and is not affiliated with or endorsed by ClickHouse, Inc. Use of the name is descriptive and remains subject to the [ClickHouse trademark policy](https://clickhouse.com/legal/trademark-policy). No ClickHouse logo is used as this project's mark.

## Red Hat Universal Base Image

The base and installed runtime RPMs come only from Red Hat UBI 9 images and UBI repositories. UBI content is freely redistributable subject to the [Red Hat UBI EULA and the components' individual open-source licenses](https://developers.redhat.com/articles/ubi-faq). Red Hat support is not included with this community image; support for Red Hat technologies depends on the applicable subscription and supported deployment combination.

The image retains RPM license texts under `/usr/share/licenses`. Its SPDX SBOM uses Syft for the exact RPM inventory and explicitly declares the three ClickHouse TGZ components from the pinned `Containerfile` inputs. Because the final image is assembled from multiple works under multiple licenses, the OCI `org.opencontainers.image.licenses=Apache-2.0` label describes this packaging project; consumers must also review the SBOM, embedded notices, ClickHouse license, UBI EULA, and component licenses.

## Release review

Before publishing a release:

1. Confirm every installed Red Hat package comes from a UBI repository and remains redistributable.
2. Inspect the release SBOM for new packages, licenses marked unknown, or missing license files.
3. Confirm ClickHouse archive license files remain in the final image.
4. Retain upstream copyright, license, attribution, and trademark notices.
5. Update this notice if the base, package source, archive contents, branding, or distribution channels change.

This notice is operational documentation, not legal advice.
