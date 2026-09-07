# OpenShift qualification procedure

This procedure qualifies one exact image digest on one exact OpenShift cluster.
It intentionally uses only namespace-scoped resources and the default
`restricted-v2` Security Context Constraint (SCC). It does not request
`anyuid`, privileged access, host paths, host namespaces, or added capabilities.

The manifests in `tests/openshift/` are qualification fixtures, not a
production topology. Reusable production overlays, operators, availability,
NetworkPolicy, backup automation, and monitoring belong in
`clickhouse-production-stack`.

## 1. Choose and record a cluster

Preferred evidence comes from a supported multi-node OpenShift cluster matching
the intended production release. If one is unavailable, use one of these
non-equivalent options:

1. The [Developer Sandbox](https://developers.redhat.com/developer-sandbox/FAQ)
   is a no-cost, time-limited, shared OpenShift environment. It is useful for
   SCC, Route, arbitrary-UID, and basic PVC evidence, but quotas, storage, and
   administrative visibility are limited.
2. [OpenShift Local/CRC](https://crc.dev/docs/installing/) provides a local
   single-node cluster. Current minimums for the OpenShift preset are four
   physical CPU cores, 10.5 GB RAM, and 35 GB disk; nested virtualization is not
   supported. It is useful for repeatable functional work, not high-availability
   or production performance evidence.
3. Kind, K3s, or upstream Kubernetes can validate portable manifests but cannot
   establish OpenShift SCC, Route, RHCOS, or support claims.

For Developer Sandbox, create or launch the sandbox, open the OpenShift console,
select **Copy login command**, and run the provided `oc login` command locally.
Use the project assigned to your account if project creation is prohibited.

For CRC on Windows 11 Pro/Enterprise or a supported Linux/macOS host:

```console
crc setup
crc config set preset openshift
crc start
crc oc-env
oc login -u developer -p developer https://api.crc.testing:6443
```

Use the current credentials printed by `crc start` if they differ. A Red Hat
account and OpenShift pull secret are required for the OpenShift preset.

Record the environment before changing it:

```console
oc version
oc whoami
oc whoami --show-server
oc get clusterversion version -o jsonpath='{.status.desired.version}{"\n"}'
oc get nodes -o wide
oc get storageclass
oc auth can-i use scc/restricted-v2
oc auth can-i use scc/anyuid
```

An ordinary Developer Sandbox user might not be allowed to list nodes, storage
classes, or SCC use. Record `forbidden` as a cluster visibility limitation;
do not request elevated access merely to make the command succeed.

## 2. Establish variables and an evidence directory

Run the remaining commands in Bash or Git Bash from the repository root:

```console
export PROJECT=clickhouse-qualification
export IMAGE_REF='ghcr.io/datopsis/clickhouse-server-ubi9@sha256:<64-hex-digest>'
export EVIDENCE_DIR="openshift-evidence-$(date -u +%Y%m%dT%H%M%SZ)"
export SECRET_DIR="$(mktemp -d)"
umask 077
mkdir -p "${EVIDENCE_DIR}"
test "${IMAGE_REF#*@sha256:}" != "${IMAGE_REF}"
```

Use an immutable manifest-list or architecture-specific digest, never a tag.
Do not commit `EVIDENCE_DIR`, `SECRET_DIR`, generated manifests, passwords,
certificates, tokens, or private keys.

Create or select the project:

```console
oc new-project "${PROJECT}" 2>/dev/null || oc project "${PROJECT}"
oc project -q | tee "${EVIDENCE_DIR}/project.txt"
oc get resourcequota,limitrange -o yaml > "${EVIDENCE_DIR}/quota.yaml"
```

If the image is private, create a pull secret without writing the registry token
to shell history, then link it only to the qualification service account:

```console
read -rsp 'GHCR user: ' GHCR_USER; echo
read -rsp 'GHCR token: ' GHCR_TOKEN; echo
oc create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_TOKEN}"
unset GHCR_USER GHCR_TOKEN
```

After applying `serviceaccount.yaml`, run
`oc secrets link clickhouse-qualification ghcr-pull --for=pull`. Skip this for
a publicly readable GHCR package.

## 3. Create infrastructure and determine certificate names

```console
oc apply -f tests/openshift/serviceaccount.yaml
oc apply -f tests/openshift/configmap.yaml
oc apply -f tests/openshift/pvc.yaml
oc apply -f tests/openshift/service.yaml
oc apply -f tests/openshift/route.yaml
export ROUTE_HOST="$(oc get route clickhouse-https -o jsonpath='{.spec.host}')"
test -n "${ROUTE_HOST}"
printf '%s\n' "${ROUTE_HOST}" | tee "${EVIDENCE_DIR}/route-host.txt"
```

The Route uses TLS passthrough, so the router does not hold the server key and
ClickHouse presents the certificate. OpenShift documents passthrough as sending
the encrypted connection directly to the destination service.

## 4. Issue ephemeral qualification credentials

Use the organization's CA for formal acceptance. The following disposable CA
is only for an isolated qualification run:

```console
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 2 \
  -keyout "${SECRET_DIR}/ca.key" -out "${SECRET_DIR}/ca.crt" \
  -subj '/CN=ClickHouse OpenShift Qualification CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl req -new -newkey rsa:3072 -sha256 -nodes \
  -keyout "${SECRET_DIR}/tls.key" -out "${SECRET_DIR}/tls.csr" \
  -subj "/CN=${ROUTE_HOST}"
printf '%s\n' \
  'basicConstraints=critical,CA:FALSE' \
  'keyUsage=critical,digitalSignature,keyEncipherment' \
  'extendedKeyUsage=serverAuth' \
  "subjectAltName=DNS:${ROUTE_HOST},DNS:clickhouse,DNS:clickhouse.${PROJECT},DNS:clickhouse.${PROJECT}.svc,DNS:clickhouse.${PROJECT}.svc.cluster.local" \
  > "${SECRET_DIR}/server.ext"
openssl x509 -req -sha256 -days 2 \
  -in "${SECRET_DIR}/tls.csr" \
  -CA "${SECRET_DIR}/ca.crt" -CAkey "${SECRET_DIR}/ca.key" \
  -CAcreateserial -extfile "${SECRET_DIR}/server.ext" \
  -out "${SECRET_DIR}/tls.crt"
openssl verify -CAfile "${SECRET_DIR}/ca.crt" "${SECRET_DIR}/tls.crt"
openssl x509 -in "${SECRET_DIR}/tls.crt" \
  -noout -subject -issuer -serial -dates -ext subjectAltName \
  > "${EVIDENCE_DIR}/certificate.txt"
```

Generate a random password without printing it:

```console
openssl rand -base64 32 > "${SECRET_DIR}/password"
oc create secret generic clickhouse-password \
  --from-file=password="${SECRET_DIR}/password"
oc create secret tls clickhouse-tls \
  --cert="${SECRET_DIR}/tls.crt" \
  --key="${SECRET_DIR}/tls.key"
oc create secret generic clickhouse-ca \
  --from-file=ca.crt="${SECRET_DIR}/ca.crt"
```

Never retain the Secret YAML or CA/server private keys as evidence.

## 5. Render and deploy the exact digest

`IMAGE_REFERENCE` deliberately prevents accidental application of an unpinned
fixture. Render it into the private evidence directory:

```console
sed "s|IMAGE_REFERENCE|${IMAGE_REF}|g" \
  tests/openshift/deployment.yaml \
  > "${EVIDENCE_DIR}/deployment.rendered.yaml"
oc apply -f "${EVIDENCE_DIR}/deployment.rendered.yaml"
oc rollout status deployment/clickhouse --timeout=10m
oc get deployment,pod,service,route,pvc -o wide \
  > "${EVIDENCE_DIR}/resources.txt"
```

If the PVC remains Pending, inspect `oc describe pvc clickhouse-data`. Select a
default-compatible storage class or reduce the requested size; record any
change. Do not silently switch to ephemeral storage.

## 6. Prove restricted, arbitrary-UID operation

```console
export POD="$(oc get pod -l app.kubernetes.io/name=clickhouse-qualification \
  -o jsonpath='{.items[0].metadata.name}')"
oc get pod "${POD}" -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}' \
  | tee "${EVIDENCE_DIR}/scc.txt"
oc exec "${POD}" -- id | tee "${EVIDENCE_DIR}/identity.txt"
oc exec "${POD}" -- sh -c 'test "$(id -u)" -ne 0'
oc exec "${POD}" -- sh -c \
  'test -w /var/lib/clickhouse && test -w /tmp && test ! -w /usr'
oc get pod "${POD}" -o jsonpath='{.spec.securityContext}{"\n"}{.spec.containers[0].securityContext}{"\n"}' \
  > "${EVIDENCE_DIR}/security-context.txt"
oc describe pod "${POD}" > "${EVIDENCE_DIR}/pod-describe.txt"
```

Require `restricted-v2`, a nonzero assigned UID, no added capabilities,
`RuntimeDefault` seccomp, no privilege escalation, and a read-only root. A
different SCC is a failed qualification unless the security owner approved and
documented it before the test.

## 7. Test ingress HTTPS and native TLS

Host-to-Route HTTPS, including CA and DNS identity:

```console
export PASSWORD="$(cat "${SECRET_DIR}/password")"
test "$(curl --silent --show-error --fail \
  --cacert "${SECRET_DIR}/ca.crt" \
  --user "default:${PASSWORD}" \
  "https://${ROUTE_HOST}/?query=SELECT%201")" = 1
```

Require wrong-CA and wrong-hostname failures. Do not use `--insecure`:

```console
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -keyout "${SECRET_DIR}/wrong-ca.key" \
  -out "${SECRET_DIR}/wrong-ca.crt" -subj '/CN=Unrelated CA'
if curl --silent --fail --cacert "${SECRET_DIR}/wrong-ca.crt" \
  --user "default:${PASSWORD}" \
  "https://${ROUTE_HOST}/?query=SELECT%201"; then
  echo 'Unrelated CA was accepted' >&2; exit 1
fi
if openssl s_client -connect "${ROUTE_HOST}:443" \
  -servername "${ROUTE_HOST}" -CAfile "${SECRET_DIR}/ca.crt" \
  -verify_hostname wrong.example -verify_return_error \
  </dev/null >/dev/null 2>&1; then
  echo 'Wrong hostname was accepted' >&2; exit 1
fi
```

Render the in-cluster client and test service DNS plus native TLS:

```console
sed "s|IMAGE_REFERENCE|${IMAGE_REF}|g" \
  tests/openshift/client-pod.yaml \
  > "${EVIDENCE_DIR}/client.rendered.yaml"
oc apply -f "${EVIDENCE_DIR}/client.rendered.yaml"
oc wait --for=condition=Ready pod/clickhouse-qualification-client --timeout=5m
oc exec clickhouse-qualification-client -- bash -c \
  'exec env -u CLICKHOUSE_CONFIG clickhouse-client \
    --config-file /etc/clickhouse-client/client.xml \
    --secure --host clickhouse --port 9440 --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --query "SELECT 1"'
```

Require a clear-text native client sent to `9440` to fail:

```console
if oc exec clickhouse-qualification-client -- bash -c \
  'clickhouse-client --host clickhouse --port 9440 --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --connect_timeout 5 --query "SELECT 1"' >/dev/null 2>&1; then
  echo 'Clear-text native connection was accepted' >&2; exit 1
fi
```

Test clear-text HTTP against the HTTPS listener through a temporary local
forward. The background process is stopped even when the assertion fails:

```console
oc port-forward service/clickhouse 18443:8443 \
  > "${EVIDENCE_DIR}/port-forward.log" 2>&1 &
export PORT_FORWARD_PID=$!
sleep 3
if curl --silent --fail --max-time 5 \
  'http://127.0.0.1:18443/ping' >/dev/null 2>&1; then
  kill "${PORT_FORWARD_PID}"; wait "${PORT_FORWARD_PID}" || true
  echo 'Clear-text HTTP was accepted' >&2; exit 1
fi
kill "${PORT_FORWARD_PID}"; wait "${PORT_FORWARD_PID}" || true
unset PORT_FORWARD_PID
```

Record sanitized results, not passwords or full command traces.

## 8. Test initialization, persistence, deletion, and recovery

```console
oc exec "${POD}" -- bash -c \
  'clickhouse-client --secure --host 127.0.0.1 --port 9440 \
    --accept-invalid-certificate --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --multiquery --query "CREATE TABLE IF NOT EXISTS default.oc_test \
      (id UInt64, value String) ENGINE=MergeTree ORDER BY id; \
      INSERT INTO default.oc_test VALUES (1, '\''persistent'\'');"'
export OLD_POD="${POD}"
oc delete pod "${OLD_POD}" --wait=true --timeout=2m
oc rollout status deployment/clickhouse --timeout=10m
export POD="$(oc get pod -l app.kubernetes.io/name=clickhouse-qualification \
  -o jsonpath='{.items[0].metadata.name}')"
test "${POD}" != "${OLD_POD}"
oc exec "${POD}" -- bash -c \
  'test "$(clickhouse-client --secure --host 127.0.0.1 --port 9440 \
    --accept-invalid-certificate --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --query "SELECT count() FROM default.oc_test")" = 1'
```

Capture events and logs before and after deletion. Confirm the old pod terminates
within the 60-second grace period and no forced kill or unclean-shutdown message
appears. A single-node CRC run validates lifecycle mechanics, not node drain.

## 9. Exercise logical backup and restore

The following qualification backup is local, sensitive evidence. Production
backup design belongs in the production stack:

```console
oc exec "${POD}" -- bash -c \
  'clickhouse-client --secure --host 127.0.0.1 --port 9440 \
    --accept-invalid-certificate --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --query "SELECT * FROM default.oc_test FORMAT Native"' \
  > "${SECRET_DIR}/oc-test.native"
sha256sum "${SECRET_DIR}/oc-test.native" \
  > "${EVIDENCE_DIR}/backup.sha256"
oc exec "${POD}" -- bash -c \
  'clickhouse-client --secure --host 127.0.0.1 --port 9440 \
    --accept-invalid-certificate --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --query "TRUNCATE TABLE default.oc_test"'
oc exec -i "${POD}" -- bash -c \
  'clickhouse-client --secure --host 127.0.0.1 --port 9440 \
    --accept-invalid-certificate --user default \
    --password "$(cat /run/secrets/clickhouse-password/password)" \
    --query "INSERT INTO default.oc_test FORMAT Native"' \
  < "${SECRET_DIR}/oc-test.native"
```

Verify the count and value after restore. Do not retain the data file if it
contains production-like information.

## 10. Prove the non-writable-volume failure

```console
sed "s|IMAGE_REFERENCE|${IMAGE_REF}|g" \
  tests/openshift/nonwritable-pod.yaml \
  > "${EVIDENCE_DIR}/nonwritable.rendered.yaml"
oc apply -f "${EVIDENCE_DIR}/nonwritable.rendered.yaml"
oc wait --for=jsonpath='{.status.phase}'=Failed \
  pod/clickhouse-nonwritable-test --timeout=3m || true
oc logs pod/clickhouse-nonwritable-test \
  > "${EVIDENCE_DIR}/nonwritable.log" 2>&1
grep -F 'Required ClickHouse directory is not writable' \
  "${EVIDENCE_DIR}/nonwritable.log"
```

The message must include the effective UID/GID and path without exposing a
secret. Admission failure instead of the intended runtime failure must be
recorded and diagnosed separately.

## 11. Diagnose failures without weakening security

Use these commands before changing a manifest:

```console
oc get pod,replicaset,deployment,pvc,route
oc describe deployment/clickhouse
oc describe pod -l app.kubernetes.io/name=clickhouse-qualification
oc get events --sort-by=.lastTimestamp
oc logs deployment/clickhouse
oc logs deployment/clickhouse --previous
oc get route clickhouse-https -o yaml
oc get endpointslice -l kubernetes.io/service-name=clickhouse -o yaml
oc describe pvc clickhouse-data
```

Interpret common outcomes:

| Symptom | Evidence to inspect | Corrective boundary |
| --- | --- | --- |
| SCC/admission rejection | Pod events and admission message | Remove unsupported fields; do not request `anyuid` or privileged SCC |
| `ImagePullBackOff` | Pod events and digest visibility | Confirm digest/architecture and namespace-scoped pull secret |
| PVC Pending | PVC events, storage class, quota | Select approved RWO storage or adjust requested capacity |
| `permission denied` | Entry-point path plus effective UID/GID | Provision volume ownership/ACL; do not add root or recursive `chown` |
| Probe failure | Current/previous logs and direct health command | Fix password/TLS mount or listener; do not remove probes |
| Route TLS failure | Route host, certificate SAN/chain, Service endpoint | Reissue correct certificate or fix target port; never use insecure verification |
| `CrashLoopBackOff` | Previous logs, exit code, events, mounts | Correct the underlying config/storage/secret fault; do not increase privileges |

After a correction, restart the procedure from the affected setup step and
retain both the failed and successful sanitized evidence.

## 12. Collect evidence and clean up

```console
oc get events --sort-by=.lastTimestamp > "${EVIDENCE_DIR}/events.txt"
oc logs deployment/clickhouse > "${EVIDENCE_DIR}/clickhouse.log"
oc get deployment clickhouse -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' \
  > "${EVIDENCE_DIR}/image.txt"
oc delete pod clickhouse-qualification-client clickhouse-nonwritable-test \
  --ignore-not-found
oc delete deployment,service,route,configmap,serviceaccount \
  -l app.kubernetes.io/name=clickhouse-qualification --ignore-not-found
oc delete deployment clickhouse --ignore-not-found
oc delete service clickhouse --ignore-not-found
oc delete route clickhouse-https --ignore-not-found
oc delete configmap clickhouse-qualification-config --ignore-not-found
oc delete serviceaccount clickhouse-qualification --ignore-not-found
oc delete secret clickhouse-password clickhouse-tls clickhouse-ca ghcr-pull \
  --ignore-not-found
oc delete pvc clickhouse-data --ignore-not-found
unset PASSWORD
rm -rf "${SECRET_DIR}"
```

Delete the project only if it was created solely for this test and policy permits
it. Review evidence for tokens, passwords, private keys, internal hostnames, and
sensitive data before attaching it to a pull request. Record failures and
limitations; never edit evidence to imply success.

## Acceptance record

The release pull request must state the OpenShift version and cluster type,
node architecture, SCC, assigned UID/GID, storage class/access mode, image
digest, Route mode, certificate subject/issuer/SAN/serial/expiry, positive and
negative TLS results, probe behavior, PVC replacement result, backup/restore
result, shutdown result, non-writable failure, commands, sanitized logs, and
reviewer/date. Until that record exists, OpenShift remains unvalidated.
