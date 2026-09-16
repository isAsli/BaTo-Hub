# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.0.3 | Yes |
| < 0.0.3 | No |

Security fixes are applied to the latest release on the `main` branch. Older releases are not maintained. Upgrade with `BaToHub --update`.

## Reporting a Vulnerability

Send vulnerability reports to **@DatPHP**. Include:

- the BaToHub version (`BaToHub --version`);
- the affected file or command;
- the steps that reproduce the problem;
- the impact you believe it has;
- a proposed fix if you have one.

Do not open a public issue for a vulnerability before it has been reviewed. Do not include private keys, passwords or tokens in a report; describe the exposure instead.

## Scope

In scope:

- the BaToHub source code, its installer, the uninstaller and the release scripts;
- the panel and tool modules shipped in this repository;
- the backup, restore and import flows;
- the self-update flow, including rollback;
- file permissions applied by BaToHub;
- handling of certificates and private keys managed by BaToHub.

## Out of Scope

- the panels themselves and their official installers;
- vulnerabilities in acme.sh, curl, systemd, or the Linux kernel;
- misconfiguration of a panel performed outside BaToHub;
- servers where another administrator already has root access and rewrites BaToHub files;
- physical access to the server.

## Response Timeline

- Acknowledgement of a report: within 7 days.
- Initial assessment: within 14 days.
- Fix or mitigation plan: within 30 days for issues that affect confidentiality, integrity or availability of a supported installation.

There is no bug bounty program.

## Security Model

### Integrity Manifest

BaToHub records a SHA-256 entry for every file it ships, in `${CONFIG_DIR}/integrity.sha256`, written atomically under a file lock. The check runs on demand (`BaToHub --check`), after every update, and at the start of an interactive session. A missing manifest is a hard failure. The manifest detects changes between a recorded state and the current files and reports them; it does not prevent a change.

### File Permissions

- Configuration and state files: mode 0600.
- `/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub`: mode 0750, owner root.
- Private keys: mode 0600, never printed, never logged.
- Backup archives and checksums: mode 0600.

### Update Verification

The self-update and the installer download a pinned release, never the `main` branch:

1. The newest published release tag is resolved through the GitHub API over HTTPS.
2. The release asset and its `manifest.json` are downloaded over HTTPS with certificate validation (`--proto '=https' --tlsv1.2 --fail`).
3. The asset SHA-256 is verified against the published `.sha256` sidecar. When the sidecar is unavailable, the SHA-256 recorded in `manifest.json` is used instead. When neither is available the download is refused.
4. Nothing is extracted before verification passes.

Protected paths are never overwritten by an update: `/etc/batohub/batohub.conf`, `/etc/batohub/panel.conf`, `/var/lib/batohub`, `/var/log/batohub`, and every path listed in `USER_MANAGED_PATHS`. A snapshot of the installation tree is taken before files are replaced, and the previous tree is restored when post-update verification fails.

### What BaToHub Does Not Do

- BaToHub does not prevent a root user from modifying files on the same server.
- BaToHub does not review the code of the official panel installers it downloads and executes. Those installers are executed as supplied by their authors.
- BaToHub does not audit acme.sh.
- BaToHub does not make outbound calls except the downloads the operator requests: the release assets during install or update, the ACME API during certificate issuance, and a public IP lookup for the status view.
- BaToHub has not undergone an independent security audit or a penetration test.

## Verification Performed Before Release

Every release is verified before publication:

- `scripts/checks.sh` passes: shell syntax, shellcheck, shfmt formatting, JSON metadata, panel and tool interfaces, version consistency, the release manifest, documentation presence, and text hygiene.
- `scripts/build-release.sh` builds the archive from the files git tracks, so an untracked or unreviewed file cannot reach a release, then verifies every archive member against `manifest.json` and the archive against its `.sha256` sidecar. The release job stops when either check fails.
- `scripts/verify-install.sh` passes: an isolated install that exercises the documented commands, the panel interface for all five panels, template apply, backup, restore, panel selection, and uninstall.
- `scripts/container-verify.sh` passes against `ubuntu:22.04` and `debian:12`: installation into a clean distribution userland, followed by the documented commands, tamper detection, and uninstall. The pipeline runs these checks in CI and on every release, and their logs are attached to workflow runs as artifacts named `container-verify-ubuntu-2204` and `container-verify-debian-12`.

These checks are structural and functional verification of BaToHub itself. They are not a behavioral test of any panel against a live upstream installation.

## Known Limitations

- The update mechanism trusts the configured GitHub repository over HTTPS. An attacker who controls that repository, or the account that publishes its releases, can publish a different tree. Verifying the SHA-256 against the release assets narrows this to whoever can publish a release; it does not remove the trust.
- Release archives are signed with GPG only when a `SIGNING_KEY` secret is configured. When no key is configured, the release carries SHA-256 checksums only, and no signature is claimed anywhere.
- Panel-specific correctness is verified structurally (interface functions, declared paths, version reporting). It is not verified behaviorally against live upstream panel installations as part of the release pipeline.
- Restore validation rejects absolute paths, parent traversal, undeclared members, and symlinks outside the BaToHub destination roots, but it cannot protect against an attacker who can already write to the BaToHub state directory.
- A backup archive contains panel configuration, which can include secrets. The archives are mode 0600 and owned by root, and they are not encrypted.

## No Bug Bounty

There is no bug bounty program at this time.
