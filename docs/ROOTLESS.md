# Rootless storage and permissions

The image starts ClickHouse directly as UID `101`, group `0`, and does not contain a root phase that changes mounted-file ownership. A runtime may assign another non-root UID, as OpenShift commonly does, provided that identity can traverse and write every configured local directory.

This model prevents startup scripts from recursively changing production data ownership and works naturally with restricted security policies. It also means the operator must provision storage correctly before starting the server. The entrypoint reports the first required path it cannot create or write together with its effective UID and GID.

## Official-image compatibility and the removed variable

`CLICKHOUSE_DATA_DIR` was an unreleased interface from this Datopsis image; it is not an environment variable provided by the official ClickHouse image. Removing it makes the two images more consistent: both now read the primary data location from the effective ClickHouse `<path>` configuration, whose upstream default is `/var/lib/clickhouse/`.

The important difference is directory ownership. The official image normally starts its entrypoint as root, discovers configured paths, creates or changes their ownership, and then launches ClickHouse as its runtime user. This image starts non-root, discovers the same classes of local path, creates permitted subdirectories, and fails with preparation instructions when the mount itself is not writable. It never repairs ownership.

The equivalent of choosing a data location for a particular `docker run` is to mount a ClickHouse configuration fragment and the corresponding volume in that command. Create `storage.xml` in the current directory:

```xml
<?xml version="1.0"?>
<clickhouse>
    <path>/data/clickhouse/</path>
</clickhouse>
```

Prepare the host directory for the image's UID and group, then start the container:

```console
sudo install -d -m 0770 -o 101 -g 0 /srv/clickhouse/data
docker run --detach --name clickhouse \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges \
  --volume ./storage.xml:/etc/clickhouse-server/config.d/storage.xml:ro \
  --volume /srv/clickhouse/data:/data/clickhouse \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

This remains runtime-selectable container configuration: no derived image is required. The difference is that the value is expressed in ClickHouse XML rather than an environment variable, preventing the entrypoint and server from using conflicting locations. Deployment automation may render the XML or ConfigMap before creating the container, but the resulting `<path>` and mounted volume must agree.

This short example moves only the primary data path. The [complete custom-path procedure](#custom-primary-data-path) also relocates temporary data, user files, and format schemas. Additional ClickHouse disks require one configured `<path>`, one writable mount, and the same host-side permission preparation per disk; see [Additional local disks](#additional-local-disks).

| Behavior | Official image | Datopsis UBI image |
| --- | --- | --- |
| Default path | `/var/lib/clickhouse/` | `/var/lib/clickhouse/` |
| Custom path source | Effective ClickHouse configuration | Effective ClickHouse configuration |
| Environment variable named `CLICKHOUSE_DATA_DIR` | No | No |
| Default entrypoint identity | Root, then drops privileges | Non-root throughout |
| Can recursively repair volume ownership | Yes, in its root startup mode | No |
| Custom path can be selected without rebuilding | Yes, with mounted configuration | Yes, with mounted configuration |

## Default named volume

The image declares `/var/lib/clickhouse` and creates it as `101:0` with group permissions matching the owner. A new Docker or Podman named volume therefore works without an ownership-changing startup step:

```console
docker volume create clickhouse-data
docker run --detach --name clickhouse \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges \
  --volume clickhouse-data:/var/lib/clickhouse \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

The `/tmp` mount is required with a read-only root filesystem. The entrypoint writes its generated users configuration under `/tmp/clickhouse-entrypoint`; ClickHouse table data remains on the persistent configured data path.

## Linux bind mount

Prepare a host directory for the fixed image identity before starting the container:

```console
sudo install -d -m 0770 -o 101 -g 0 /srv/clickhouse/data
docker run --detach --name clickhouse \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges \
  --volume /srv/clickhouse/data:/var/lib/clickhouse \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

On an SELinux-enforcing Podman or Docker host, add `:Z` for a private relabel, for example `/srv/clickhouse/data:/var/lib/clickhouse:Z`. Coordinate labeling with the host administrator when the same content must be shared; do not disable SELinux to work around a denial.

If organizational policy assigns a different UID while retaining writable group `0`, prepare shared content according to the OpenShift-compatible image convention:

```console
sudo chgrp -R 0 /srv/clickhouse/data
sudo chmod -R g=u /srv/clickhouse/data
```

Avoid `chmod 0777`. It grants write access to identities outside the intended container security context.

## Kubernetes and OpenShift volumes

For a Kubernetes deployment with the image's fixed identity, start with this pod-level security context and verify that the selected CSI driver honors it:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 101
  runAsGroup: 0
  fsGroup: 0
  fsGroupChangePolicy: OnRootMismatch
```

The container-level policy should additionally set `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`, and `seccompProfile.type: RuntimeDefault`. Mount an `emptyDir` at `/tmp` and the PVC at the effective ClickHouse data path.

Under OpenShift's restricted SCC, omit a fixed `runAsUser` when the project must use its assigned UID range. Keep the image directories group-0 writable, inspect the actual identity with `oc exec <pod> -- id`, and confirm the storage class makes the PVC writable to that pod. Do not request `anyuid`, privileged mode, or root solely to repair storage.

`fsGroup` behavior, recursive ownership changes, and mount startup time vary by CSI driver. NFS with root squash can prevent both kubelet and administrators acting as root from changing ownership. In that case, provision the export with the required UID/GID or ACL on the storage server; the container cannot repair it.

## Custom primary data path

ClickHouse configuration is the only source of truth for storage. `CLICKHOUSE_DATA_DIR` is intentionally unsupported because changing an environment variable alone does not change ClickHouse's `<path>` setting.

Create a configuration fragment such as `storage.xml`:

```xml
<?xml version="1.0"?>
<clickhouse>
    <path>/data/clickhouse/</path>
    <tmp_path>/data/clickhouse-tmp/</tmp_path>
    <user_files_path>/data/user-files/</user_files_path>
    <format_schema_path>/data/format-schemas/</format_schema_path>
</clickhouse>
```

Provision every top-level mount and mount the fragment read-only:

```console
sudo install -d -m 0770 -o 101 -g 0 \
  /srv/clickhouse/data /srv/clickhouse/tmp \
  /srv/clickhouse/user-files /srv/clickhouse/format-schemas

docker run --detach --name clickhouse \
  --env CLICKHOUSE_PASSWORD='replace-me' \
  --read-only --tmpfs /tmp:size=256m,mode=1777 \
  --cap-drop ALL --security-opt no-new-privileges \
  --volume ./storage.xml:/etc/clickhouse-server/config.d/storage.xml:ro \
  --volume /srv/clickhouse/data:/data/clickhouse \
  --volume /srv/clickhouse/tmp:/data/clickhouse-tmp \
  --volume /srv/clickhouse/user-files:/data/user-files \
  --volume /srv/clickhouse/format-schemas:/data/format-schemas \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
```

At startup the entrypoint reads the effective `path`, `tmp_path`, `user_files_path`, and `format_schema_path`. Relative auxiliary paths are resolved below the primary data path. The primary `<path>` must be absolute so its persistent-storage boundary is unambiguous.

## Additional local disks

An additional local disk needs both a ClickHouse configuration entry and a writable mount:

```xml
<?xml version="1.0"?>
<clickhouse>
    <storage_configuration>
        <disks>
            <archive>
                <path>/data/archive/</path>
            </archive>
        </disks>
    </storage_configuration>
</clickhouse>
```

Prepare `/srv/clickhouse/archive` using the same UID/GID or group-based procedure, then mount it at `/data/archive`. The entrypoint discovers every configured disk `path` and `metadata_path`, creates missing subdirectories where permitted, and fails before launching the server when a required local location is not writable. Object-storage credentials and remote endpoints have their own configuration and are not made valid by local directory preparation.

## Troubleshooting

For an error such as:

```text
Required ClickHouse directory is not writable: /data/archive
Container identity: uid=100123 gid=0
```

check the container identity, mount flags, ownership, mode, ACL, SELinux label, and storage backend:

```console
docker inspect clickhouse --format '{{.Config.User}} {{json .Mounts}}'
docker run --rm --entrypoint id \
  ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<digest>
namei -l /srv/clickhouse/archive
getfacl /srv/clickhouse/archive
ls -ldZ /srv/clickhouse/archive
```

For Kubernetes or OpenShift, also inspect `id`, the pod security context, PVC events, and the mounted directory from a diagnostic pod using the same security context. Correct the storage provisioning or workload identity outside the running ClickHouse container. Do not solve the problem by starting the database as root, adding broad capabilities, disabling SELinux, or making the volume world-writable.
