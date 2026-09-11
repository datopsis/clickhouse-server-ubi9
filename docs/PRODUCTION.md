# Production deployment guide

Production readiness is a property of a tested deployment, not an image label. Complete this runbook for the exact image digest, architecture, ClickHouse topology, storage class, configuration, and platform that will be operated.

## 1. Choose the architecture and support boundary

- Decide whether one node is sufficient. A single node has no database-service high availability; use ClickHouse replication and Keeper only after designing failure domains, quorum, inter-server authentication, and recovery.
- Use a ClickHouse LTS line when long maintenance windows matter, and document the supported UBI/ClickHouse combinations and end-of-support date.
- Assign owners for the image, database, storage, certificates, backups, vulnerability triage, and incident response.
- Pin `ghcr.io/datopsis/clickhouse-ubi@sha256:<digest>`. Verify the release signature, SBOM, and provenance before promotion. Never deploy a failed or unsigned candidate tag.

## 2. Prepare identity and secrets

- Run non-root with `runAsUser: 101`, `runAsGroup: 0`, or a platform-assigned OpenShift UID with group `0`. Set `runAsNonRoot`, drop all capabilities, enable `no-new-privileges`, and use the runtime default seccomp profile.
- Store the password in a Podman/Kubernetes secret and set `CLICKHOUSE_PASSWORD_FILE`; do not put it in a manifest, command history, or image layer.
- Create named users and roles with SQL or mounted `users.d` fragments. The environment-variable interface intentionally manages only `default`.
- Rotate credentials and certificates through a rehearsed rolling procedure. See [TLS certificates and trust](TLS.md).

## 3. Provision durable storage

- Mount durable, low-latency storage at the effective ClickHouse `<path>`, which defaults to `/var/lib/clickhouse`. Configure custom paths in ClickHouse XML rather than an environment variable. Size it for data, merges, mutations, temporary work, replication backlog, and recovery headroom—not only current table bytes.
- Set permissions for UID `101`, group `0`, and group write, or validate the platform's arbitrary-UID policy. Test the actual CSI/NFS/storage backend; root-squash and `fsGroup` behavior vary.
- Provision every configured local disk and metadata path before startup. Follow [rootless storage and permissions](ROOTLESS.md) for named volumes, bind mounts, Kubernetes/OpenShift identities, SELinux, and failure diagnostics.
- Keep the root filesystem read-only and mount `/tmp` as a bounded `tmpfs`. Do not place durable data or backups in the container writable layer.
- Define disk-full alerts and retention policies. A persistent volume is not a backup.

## 4. Configure networking and TLS

- Expose only interfaces clients actually use. Restrict `8123`/`8443` and `9000`/`9440` by network policy and firewall. Never expose inter-server port `9009` or `9010` to untrusted networks.
- Use TLS for traffic crossing an untrusted boundary. Prefer platform TLS termination where appropriate; configure direct ClickHouse TLS for native TCP or end-to-end requirements.
- Allow-list required egress destinations. Public endpoints use the included CA store; internal services require an explicit CA bundle.
- Use stable DNS, synchronized clocks, and certificate SANs matching the names clients use.

## 5. Set resources and kernel limits

- Set `nofile=262144:262144`, as used by the smoke suite and upstream examples.
- Establish CPU and memory requests from a representative load test. Set memory limits only after accounting for queries, caches, merges, dictionaries, and concurrent background work; an arbitrary low container limit causes OOM kills.
- Align ClickHouse memory and concurrency settings with the container limit so ClickHouse rejects or queues work before the kernel kills it.
- Benchmark ingestion, representative queries, merges, restart recovery, backup, and restore on the production storage class. Record saturation thresholds and safe operating headroom.
- Add `IPC_LOCK`, `NET_ADMIN`, or `SYS_NICE` only when a tested feature requires it and the risk is approved. The baseline needs none.

This project does not publish universal CPU/memory values because workload shape and storage dominate them. Release approval requires recorded test inputs, p50/p95/p99 latency, throughput, peak memory, disk growth, and recovery time for the target deployment.

## 6. Health, startup, and shutdown

The image health check runs an authenticated local `SELECT 1`. For orchestrators, use separate probes:

- startup: allow enough time for metadata loading and recovery on the largest tested data set;
- readiness: query `/ping` or `SELECT 1` with an appropriately scoped secret so traffic stops before shutdown;
- liveness: use a conservative threshold so load spikes do not create a restart loop.

Set a termination grace period longer than the measured ClickHouse shutdown time. Confirm the runtime sends `SIGTERM` to PID 1 and waits. Test node drain, forced termination, startup after an unclean stop, and a full-volume condition.

## 7. Back up and prove restoration

- Choose a ClickHouse-supported backup design appropriate to local disks, object storage, or replicated topology. Back up access-control/configuration material and encryption keys separately from table data.
- Define recovery point and recovery time objectives, retention, immutability, off-site/off-cluster copies, and who can restore.
- Restore into an isolated environment on a schedule and validate row counts, schemas, users, dictionaries, and representative queries. A successful backup job without a restore test is insufficient evidence.
- Before an upgrade, take and validate the required backup or snapshot and retain the previous image digest and configuration for the documented rollback window.

## 8. Observe and operate

- Collect container stdout/stderr centrally. Alert on repeated restarts, failed queries, authentication failures, replica delay, Keeper quorum, background merge pressure, disk/inode exhaustion, memory pressure, certificate expiry, and backup failure.
- Scrape ClickHouse metrics and define service-level indicators for availability, ingestion lag, query latency, and correctness relevant to the workload.
- Protect logs and query history because SQL and errors can contain sensitive values. Set retention and access controls.
- Maintain dashboards, on-call routing, incident runbooks, capacity forecasts, and a tested break-glass process.

## 9. Patch and upgrade

1. Renovate proposes new ClickHouse versions and UBI digests; review upstream release notes and security advisories.
2. Build both architectures, run the smoke suite and scanners, and inspect the SBOM delta.
3. Restore a recent backup into staging and run application compatibility, performance, TLS, and failure tests.
4. Roll out through a canary or one replica at a time while monitoring merges, replication, errors, and latency.
5. Do not downgrade data files unless ClickHouse explicitly supports that path. Rollback normally means restore/recover according to the tested plan.

For unchanged ClickHouse versions, rebuild when UBI publishes relevant security updates. Review the [vulnerability process](VULNERABILITY-MANAGEMENT.md) rather than treating unfixed counts as patchable versions.

## 10. Disconnected environments

- Mirror the exact verified image digest and its release evidence through a controlled transfer station. Import into an internal registry and record the resulting internal digest mapping.
- Mirror vulnerability databases and update metadata on a defined cadence; an offline scan with a stale database is not equivalent to current CI.
- Mirror every artifact needed for rebuilds if the disconnected side must build: both UBI images by digest, ClickHouse archives and `.sha512` files, build tools, and Actions/tool binaries as applicable.
- Use an internal CA and offline certificate lifecycle as described in [TLS certificates and trust](TLS.md). Mirror time sources, package/advisory data, and revocation information required by policy.
- Rehearse image promotion, certificate renewal, vulnerability-data refresh, backup restore, and rollback entirely inside the boundary.

## Go-live evidence

Before declaring a deployment supported, retain:

- exact image/configuration digests and signature verification;
- native `amd64` or `arm64` test evidence;
- security-context, network-policy, TLS, secret, and storage review;
- representative capacity and failure-test results;
- successful backup restoration and measured recovery times;
- current vulnerability triage with owners and expiries;
- monitoring screenshots/queries, alert routing, runbooks, and support contacts;
- approved upgrade, rollback, incident, and disconnected-update procedures.

The repository's [first-release roadmap](ROADMAP.md) remains the publication gate; this document is the deployment operator's runbook.
