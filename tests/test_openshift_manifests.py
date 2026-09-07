import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST_DIR = ROOT / "tests" / "openshift"


class OpenShiftManifestTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (MANIFEST_DIR / name).read_text(encoding="utf-8")

    def test_workloads_enforce_restricted_security_context(self) -> None:
        for name in ("deployment.yaml", "client-pod.yaml", "nonwritable-pod.yaml"):
            with self.subTest(name=name):
                content = self.read(name)
                self.assertIn("runAsNonRoot: true", content)
                self.assertIn("type: RuntimeDefault", content)
                self.assertIn("automountServiceAccountToken: false", content)
                self.assertIn("allowPrivilegeEscalation: false", content)
                self.assertIn("readOnlyRootFilesystem: true", content)
                self.assertIn("- ALL", content)
                self.assertIn("image: IMAGE_REFERENCE", content)
                for forbidden in (
                    "privileged: true",
                    "hostNetwork: true",
                    "hostPID: true",
                    "hostIPC: true",
                    "hostPath:",
                    "runAsUser: 0",
                ):
                    self.assertNotIn(forbidden, content)

    def test_server_exposes_only_tls_client_ports(self) -> None:
        deployment = self.read("deployment.yaml")
        service = self.read("service.yaml")
        config = self.read("configmap.yaml")
        for content in (deployment, service):
            self.assertIn("8443", content)
            self.assertIn("9440", content)
            self.assertNotIn("8123", content)
            self.assertNotIn("9000", content)
        self.assertIn('<http_port remove="remove"/>', config)
        self.assertIn('<tcp_port remove="remove"/>', config)
        self.assertIn("verificationMode>strict", config)
        self.assertIn("RejectCertificateHandler", config)

    def test_server_uses_bounded_tmp_secrets_and_persistent_data(self) -> None:
        deployment = self.read("deployment.yaml")
        self.assertIn("sizeLimit: 256Mi", deployment)
        self.assertIn("claimName: clickhouse-data", deployment)
        self.assertIn("secretName: clickhouse-tls", deployment)
        self.assertIn("secretName: clickhouse-password", deployment)
        self.assertIn("defaultMode: 0440", deployment)
        for probe in ("startupProbe:", "readinessProbe:", "livenessProbe:"):
            self.assertIn(probe, deployment)

    def test_route_preserves_end_to_end_tls(self) -> None:
        route = self.read("route.yaml")
        self.assertIn("termination: passthrough", route)
        self.assertIn("insecureEdgeTerminationPolicy: None", route)
        self.assertIn("targetPort: https", route)


if __name__ == "__main__":
    unittest.main()
