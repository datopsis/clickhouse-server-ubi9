# Architecture and data-flow diagrams

These diagrams describe the image boundary and the reference qualification
flows. They are not production deployment manifests. Platform topology,
availability, policy, and automation belong in `clickhouse-production-stack`.

All diagrams are repository-native SVG with text alternatives and no external
assets or scripts:

1. [System context and trust boundaries](diagrams/system-context.svg)
2. [Runtime data flows](diagrams/runtime-data-flow.svg)
3. [Connected and disconnected TLS trust](diagrams/tls-trust-flows.svg)
4. [Build, release, and assurance evidence](diagrams/assurance-pipeline.svg)
5. [Security-control ownership](diagrams/control-ownership.svg)

The TLS qualification behavior is represented explicitly:

| Behavior | Diagram |
| --- | --- |
| Strict client-to-server CA and hostname checks | TLS trust flows |
| Server-side outbound public/private trust using ClickHouse's integration path | Runtime data flows and TLS trust flows |
| Dedicated authenticated loopback health client, separate from outbound trust | Runtime data flows |
| Internal-only disconnected service path and denied public egress | TLS trust flows and system context |
| Negative cases, renewal, rollback, and retained evidence | TLS trust flows and assurance pipeline |

Review and update the diagrams whenever ports, trust stores, secret paths,
build inputs, release evidence, or repository ownership boundaries change.
Each release review must compare the diagrams with the exact configuration and
deployment rather than assuming the reference flow is the deployed flow.
