# Security control engineering and SCTM export

## Current status and terminology

No DISA database STIG is written for ClickHouse, and this project has not yet
adopted or claimed compliance with any database-STIG requirement. The first
release must not be described as STIG compliant until the analysis and review
gates below are complete.

SCTM normally means **Security Control Traceability Matrix** in a DoD RMF
authorization package. An SCTM is system-level: it depends on the authorization
boundary, impact level, overlays, organization-defined parameters, inherited
controls, deployment architecture, and assessor decisions. This image cannot
truthfully produce that finished system document.

This repository will instead publish a **component control implementation and
evidence matrix** that a system owner or cyber team can consume into its SCTM.
The canonical machine-readable form will be a NIST OSCAL Component Definition,
with a generated CSV view and human-readable rationale. NIST designed the
[OSCAL Component Definition model](https://pages.nist.gov/OSCAL/learn/concepts/layer/implementation/component-definition/)
for maintainers to describe controls supported by software or containers so
system owners can reuse the information in an SSP. It describes possible
component implementations; it does not authorize a deployed system.

## Authoritative source hierarchy

Every source is downloaded from its publisher, retained outside Git when its
license or size requires that, and recorded by title, version/release, release
date, URL, retrieval date, SHA-256, and status. A superseded or sunset guide is
not a normative source.

Use this order:

1. The system's selected NIST SP 800-53 Rev. 5 baseline, overlays, and
   organization-defined parameters establish the actual control requirement.
2. The current DISA Database SRG supplies database-technology-neutral
   requirements and CCI mappings. The current Container Platform SRG and RHEL 9
   STIG are considered only for requirements genuinely owned by this image.
3. Active product STIGs for MongoDB, PostgreSQL distributions, Oracle Database,
   Oracle MySQL, Microsoft SQL Server, and other current DISA-listed databases
   are comparative implementation references. Product-specific checks and
   fixes are never copied as if they applied to ClickHouse.
4. ClickHouse and Red Hat documentation, source, configuration behavior, and
   test results establish whether ClickHouse can implement the objective.
5. NIST SP 800-53A Rev. 5 supplies the assessment-method structure. It permits
   tailored procedures, but tailoring and assessment depth remain system risk
   decisions.

The [DISA STIG library](https://public.cyber.mil/stigs/downloads/) is the source
of record. Record its current versions at implementation time; do not freeze a
version copied from a search result into the control mapping.

Existing behaviors such as non-root execution, restricted capabilities,
authentication, TLS options, console logging, path-permission checks, immutable
build inputs, and vulnerability response are **candidate implementation
evidence**, not controls already “brought over” from a STIG. The source analysis
may map some of them to Database SRG objectives, but the mapping does not exist
until its IDs, wording, applicability, and assessment procedure receive review.

## Required source-comparison register

Create `security/stig-sources.yaml` and `security/stig-analysis.csv`. The
analysis must include every Database SRG requirement and identify matching or
related items from each selected active database STIG. One row does not become
an image control merely because several database products implement it.

Each analysis row must contain:

- Database SRG ID, STIG vulnerability/rule IDs, CCI, severity, and NIST control;
- exact source title/version/hash and a short paraphrase of the objective;
- ClickHouse relevance and threat addressed;
- disposition: `adopt`, `deployment-owned`, `inherited`, `not-applicable`,
  `unsupported`, or `needs-research`;
- detailed justification, including why analogous product-STIG behavior is or
  is not transferable to ClickHouse;
- owner: image, ClickHouse configuration, runtime, platform, operator,
  organization, or shared;
- implementation and enable/disable mechanism, secure setting, compatibility
  impact, prerequisites, and residual risk;
- examine/test/interview procedure, expected result, evidence location, and
  automation status;
- reviewer, review date, expiration/revalidation trigger, and linked issue.

An `adopt` decision requires two-person review. A `not-applicable` decision
requires the same evidence quality as an adoption; absence of a package or
command in UBI Micro is not by itself adequate justification.

## Control behavior and configurability

Classify each adopted control before implementing it:

| Class | Behavior | Examples |
| --- | --- | --- |
| Image invariant | Always present; changing it requires another image | Non-root identity, no package manager/downloader, verified build inputs |
| Configurable ClickHouse control | Delivered as a documented, versioned configuration fragment or profile | TLS listeners, password policy, audit/query logging, protocol exposure |
| Deployment control | Implemented in `clickhouse-production-stack` or the target platform | NetworkPolicy, Secret store, ingress, replicas, backup schedule |
| Organizational/inherited control | Supplied and assessed outside either repository | Personnel, incident response, enterprise PKI policy, physical controls |

Where ClickHouse safely permits choice, provide explicit secure and
compatibility profiles rather than hidden entrypoint mutation or a growing set
of environment variables. For every switch, document the default, exact XML or
deployment setting, restart requirement, dependencies, loss of protection, and
verification command. A user may choose a less restrictive profile only when
the source requirement allows tailoring; the project must not label a disabled
control as implemented.

Some image invariants will intentionally not have an off switch. Controls such
as non-root execution and build checksum verification define this image's trust
boundary. Users needing different invariants should build and assess a separate
image rather than silently weakening this artifact.

## Published control artifacts

After review, publish and validate:

- `security/component-definition.json`: canonical OSCAL Component Definition;
- `security/control-matrix.csv`: deterministic tabular export for SCTM import;
- `security/stig-analysis.csv`: complete source-to-ClickHouse disposition;
- `security/stig-sources.yaml`: immutable source provenance and hashes;
- `docs/CONTROL-IMPLEMENTATION.md`: human-readable implementation,
  justification, enable/disable, residual-risk, and assessment guide;
- architecture diagrams identifying image, deployment, platform, and inherited
  ownership boundaries;
- digest-bound test and scanner evidence referenced by control rows.

Validate OSCAL against the pinned official schema, validate all identifiers and
cross-references, regenerate CSV deterministically, and fail CI on drift. Never
store passwords, private keys, deployment identifiers, assessor-only material,
or sensitive findings in public artifacts.

## Assessment and evidence rule

Each claimed control needs a procedure that states preconditions, exact target
digest/configuration, method (`examine`, `test`, or `interview`), commands,
expected and failure results, cleanup, evidence sensitivity, and assessor
limitations. Automated output supports an assessment; it is not an assessor
decision.

Claims must use precise verbs:

- **provides**: the immutable image implements the behavior;
- **supports**: the image has a documented configuration that can contribute;
- **requires**: the deployment or organization must supply it;
- **validated**: use only with the applicable independent validation and exact
  certificate/scope;
- **not assessed**: no evidence exists for the stated boundary.

Re-run affected procedures when ClickHouse, UBI, configuration, source STIG/SRG,
OSCAL schema, or the deployment boundary changes.

## Prohibited claims

Do not call this image, its TLS configuration, SCAP result, or control export
“DISA STIG certified,” “RMF authorized,” or “FIPS validated.” Only an authorized
system and its approving officials can resolve the complete SCTM and accept
residual risk.
