# FIPS and cryptographic boundary

## Current determination

This image does **not** currently claim FIPS 140-3 validation or validated
cryptography for ClickHouse TLS.

FIPS 140-3 applies to a defined cryptographic module in an approved operational
environment, not to the TLS protocol label or the container base image by
itself. NIST states that a product embedding a validated module cannot claim
that the product itself is validated, and the applicable module certificate,
version, approved mode, and operational environment must be verified in the
[CMVP database and security policy](https://csrc.nist.gov/Projects/cryptographic-module-validation-program/FAQs).

The upstream `clickhouse-common-static` binary used here is not dynamically
linked to UBI's `libssl` or `libcrypto`; local inspection of the release binary
shows only its basic glibc runtime dependencies. ClickHouse's build supports a
separate
[dynamic-OpenSSL option](https://github.com/ClickHouse/ClickHouse/blob/master/CMakeLists.txt),
while normal upstream artifacts use bundled dependencies. This project has not
identified a CMVP certificate whose module,
version, build, approved mode, and operating environment cover the embedded
cryptography in the pinned ClickHouse archive. Therefore a FIPS-enabled RHEL
host cannot, by itself, make this ClickHouse binary's TLS FIPS validated.

Red Hat also explains that container FIPS behavior starts with a FIPS-enabled
host and supported runtime; `fips-mode-setup` cannot enable FIPS inside a
container in its
[RHEL 9 security-hardening guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/switching-rhel-to-fips-mode_security-hardening).
That mechanism applies to supported RHEL cryptographic components. It does not
replace proof that ClickHouse actually uses the covered module.

## TLS protocol support is a separate question

The supplied TLS example disables SSLv2, SSLv3, TLS 1.0, and TLS 1.1. It permits
TLS 1.2 and TLS 1.3 when supported by the pinned ClickHouse build and peer. The
rehearsal tests certificate chains, trust, identity, isolation, renewal, and
rollback; it does not test or establish FIPS validation.

Operators can mount a different ClickHouse XML configuration, but this project
will not document TLS 1.0 or 1.1 as supported security profiles. Any cipher,
curve, protocol, or mutual-TLS profile must be tested with every production
client and integration. Protocol negotiation alone is not evidence that all
cryptographic services stayed inside an approved FIPS module.

## Path to a defensible FIPS offering

Treat FIPS as a separate image/build qualification, not a runtime toggle:

1. Obtain an upstream/vendor statement identifying every cryptographic service
   ClickHouse uses and whether a supported build can exclusively use a specific
   FIPS 140-3 validated module.
2. Pin the module certificate, security policy, exact package/build, approved
   mode, algorithms, architectures, and operational environments.
3. Build or obtain a ClickHouse artifact that uses that module without an
   unvalidated fallback or embedded alternative. Verify linkage and provider
   selection for every release.
4. Run on a compatible host installed in FIPS mode with the supported Podman or
   OpenShift runtime; record host and container FIPS indicators.
5. Add positive approved-algorithm tests and negative disallowed-algorithm,
   protocol, key, and fallback tests on AMD64 and ARM64.
6. Have the resulting claim and evidence reviewed by the organization's FIPS
   specialist or assessor. State only “uses module X, certificate Y, in approved
   mode within listed operational environment Z” unless the ClickHouse product
   itself obtains validation.

Until all six steps are complete, deployments requiring validated cryptography
should terminate TLS in an independently validated platform component and have
the cyber team assess the remaining clear-text or separately encrypted hop.
That architecture is not automatically acceptable; its boundary and data flow
must match the system's policy.
