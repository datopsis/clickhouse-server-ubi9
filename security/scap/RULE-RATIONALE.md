# SCAP rule rationale

This is the review record for profile
`xccdf_org.datopsis_profile_ubi9_micro_container`. It is based on the native
AMD64 and ARM64 discovery evidence for commit `c099690`, the pinned
ComplianceAsCode `0.1.82` RHEL 9 data stream, and inspection of the
Containerfile and generated reports. Both architectures produced the same 67
results other than `notapplicable` and `notselected`.

Selection means only that the rule's check is meaningful against the immutable
image filesystem and that this repository controls the result. It does not
automatically adopt every NIST, CCI, SRG, or STIG reference attached to that
rule. Those mappings often assume a complete operating system and must be
analyzed separately in the security-control engineering package.

## Selected rules

| Objective and exact ComplianceAsCode rule IDs | Image implementation | Verification and rationale |
| --- | --- | --- |
| Account database consistency: `accounts_password_all_shadowed_sha512`, `gid_passwd_group_same` | The build installs a locked, non-login `clickhouse` account and retains UBI account databases. | Offline OVAL reads the immutable `/etc/passwd`, `/etc/group`, and shadow files. The image creates these files and controls their contents. |
| Account database group ownership: `file_groupowner_etc_group`, `file_groupowner_etc_gshadow`, `file_groupowner_etc_passwd`, `file_groupowner_etc_shadow` | Account databases are root/system-group-owned in the final image. | Offline file metadata is authoritative and is unaffected by runtime volumes. |
| Account database ownership: `file_owner_etc_group`, `file_owner_etc_gshadow`, `file_owner_etc_passwd`, `file_owner_etc_shadow` | Account databases are root-owned. | A non-root runtime must not be able to replace identity data. |
| Account database modes: `file_permissions_etc_group`, `file_permissions_etc_gshadow`, `file_permissions_etc_passwd`, `file_permissions_etc_shadow` | UBI supplies restrictive modes, preserved by the build. | The scanner evaluates actual final-image modes, so this detects build or base-image drift. |
| Program directory integrity: `file_groupownership_system_commands_dirs`, `file_ownership_binary_dirs`, `file_permissions_binary_dirs` | The build normalizes the ClickHouse TGZ's release UID/GID to `0:0`; the entrypoint and other immutable program/config assets copied under `/usr` are also `0:0`. | Discovery found UID/GID 1000 on ClickHouse files and UID 101 on the entrypoint. The profile retains RHEL-09-232195/V-257919 and RHEL-09-232190/V-257918 to prevent regression. Runtime UID 101 needs execute/read access, not ownership. |
| Library integrity: `dir_group_ownership_library_dirs`, `dir_ownership_library_dirs`, `dir_permissions_library_dirs`, `file_ownership_library_dirs`, `file_permissions_library_dirs`, `root_permissions_syslibrary_files` | UBI and ClickHouse libraries are immutable, root-owned image content. | Offline ownership/mode inspection directly evaluates repository-controlled content. |
| Unsafe filesystem content: `dir_perms_world_writable_sticky_bits`, `dir_perms_world_writable_system_owned`, `file_permissions_ungroupowned` | The image build controls initial directory modes and numeric owners. | These checks detect unexpectedly writable or ungrouped immutable content. Runtime-mounted paths require separate deployment checks. |
| Host trust files: `no_host_based_files`, `no_user_host_based_files` | The image does not include legacy `.rhosts` or `/etc/hosts.equiv` trust files. | The absence is an intentional image invariant and future additions would be a regression. |
| Unneeded packages: `package_gssproxy_removed`, `package_iprutils_removed`, `package_nfs-utils_removed`, `package_telnet-server_removed`, `package_tftp-server_removed`, `package_tuned_removed`, `package_vsftpd_removed`, `xwindows_remove_packages` | The package-manager-free UBI Micro runtime excludes remote filesystems, legacy clear-text services, tuning daemons, and graphical packages. | The installed RPM database remains available to offline OVAL. These packages are unnecessary for the ClickHouse process and would expand attack surface. |

There are 36 selected rule IDs. The tailoring intentionally has no `extends`
attribute: it selects only these checks and does not inherit the complete RHEL
9 STIG profile.

## Excluded discovery results

| Discovery rules | Result | Ownership and exclusion justification | Required alternative evidence |
| --- | --- | --- | --- |
| `accounts_umask_etc_bashrc`, `accounts_umask_etc_profile` | fail | RHEL-09-412055/V-258072 and RHEL-09-412070/V-258075 govern interactive/login-shell defaults. The service account uses `/sbin/nologin`, and the exec-form entrypoint does not source either file. Changing them would not constrain files created by ClickHouse and would create false assurance. | ClickHouse-created secret modes and mounted-secret modes are tested by behavioral and deployment procedures. |
| `configure_crypto_policy`, `package_crypto-policies_installed` | fail | RHEL-09-215105/RHEL-09-672030/V-258241 and RHEL-09-215100/V-258234 assume applications consume RHEL system crypto policy. The upstream ClickHouse static binary does not establish that linkage. Installing the package or policy file alone would not prove TLS uses it. | Use the TLS rehearsal, cipher/protocol inspection, ClickHouse dependency evidence, and the FIPS boundary analysis in `docs/FIPS.md`. Do not claim FIPS from this exclusion. |
| `network_configure_name_resolution` | fail | RHEL-09-252035/V-257948 inspects `/etc/resolv.conf`, which the container runtime or orchestrator injects at deployment. Baked image content cannot guarantee redundant approved resolvers. | The deployment repository and platform qualification must inspect effective pod DNS policy and failure behavior. |
| `security_patches_up_to_date` | notchecked | RHEL-09-211015/V-257778 expects an online/system package update model. The final image has no package manager; pinned image inputs, not in-place updates, define patch state. | Trivy and Grype inventories, SBOM review, digest refresh, rebuild SLA, and vulnerability triage are the authoritative evidence. |
| `ensure_epel_repos_disabled`, `ensure_gpgcheck_never_disabled`, `ensure_redhat_gpgkey_installed` | pass | These govern repositories and package installation on a managed host. The final UBI Micro image has no package manager and is never updated in place. A pass is not a meaningful runtime control. | Containerfile digest pins, HTTPS downloads, ClickHouse SHA-512 verification, and retained build provenance. |
| `installed_OS_is_vendor_supported` | pass | Vendor lifecycle is temporal and cannot be established permanently by a filesystem result from pinned SCAP content. | `docs/SUPPORT.md`, scheduled rebuilds, and release-time UBI support review. |
| `file_groupowner_backup_etc_group`, `file_groupowner_backup_etc_gshadow`, `file_groupowner_backup_etc_passwd`, `file_groupowner_backup_etc_shadow`, `file_owner_backup_etc_group`, `file_owner_backup_etc_gshadow`, `file_owner_backup_etc_passwd`, `file_owner_backup_etc_shadow`, `file_permissions_backup_etc_group`, `file_permissions_backup_etc_gshadow`, `file_permissions_backup_etc_passwd`, `file_permissions_backup_etc_shadow` | pass | The image contains no mutable account-management workflow that creates these conventional backup files; the pass is currently an absence check rather than a used feature. | The selected primary account-database rules provide the relevant immutable-image assurance. Reconsider if account mutation tooling is added. |
| `file_groupowner_var_log`, `file_groupowner_var_log_messages`, `file_owner_var_log`, `file_owner_var_log_messages`, `file_permissions_var_log`, `file_permissions_var_log_messages` | pass | `/var/log/clickhouse-server` is a runtime-writable path and may be replaced by a volume. Root-only host log assumptions conflict with UID 101 and arbitrary OpenShift UIDs. | Deployment security context, volume permissions, log routing, and audit retention belong to the production stack. |
| `file_groupownership_home_directories`, `file_permissions_home_directories` | pass | The service account home is the persistent ClickHouse data path, which is replaced by operator-provisioned storage and must remain writable by the effective non-root identity. Host home-directory ownership assumptions are not portable to arbitrary-UID pods. | Rootless storage tests and platform-specific PVC/NFS procedures. |
| `file_permission_user_init_files_root` | pass | Interactive root login and root shell initialization are outside the non-root service-container contract. Selecting this would imply support for a root user workflow. | Runtime user metadata and smoke tests prove the process starts as UID 101; OpenShift tests cover arbitrary non-root UIDs. |

The remaining 1,473 discovery results were `notapplicable` or `notselected`.
They include kernel, boot loader, partition, mount-layout, systemd, audit,
firewall, host networking, sysctl, SELinux-mode, and FIPS-mode objectives.
They are excluded as a class because an exported container filesystem cannot
configure or prove those host/platform properties. The production deployment
and the system cyber team must determine inheritance and assess them at the
correct boundary.

## Review and change procedure

1. Re-run full STIG discovery whenever the UBI major version, OpenSCAP engine,
   ComplianceAsCode content, or profile changes.
2. Compare all rule IDs and results with this record on both architectures.
3. For each proposed selection, inspect its OVAL logic and confirm that all
   evaluated objects are immutable image content. Never select a passing rule
   merely because it passes.
4. For each exclusion, confirm the named alternative evidence exists and that
   ownership has not moved into this repository.
5. Change the profile version and review date, obtain a security-focused pull
   request review, and retain the profile hash with scan evidence.
6. Do not use automatic remediation. Make necessary changes explicitly in the
   Containerfile or repository assets so other tests and provenance cover them.
