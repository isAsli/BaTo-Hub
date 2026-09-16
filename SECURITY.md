# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.0.4 | Yes |
| < 0.0.4 | No |

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

A mismatch is reported and the interface still opens, because BaToHub is a management tool and the operator keeps control. Setting `INTEGRITY_HARD_FAIL="1"` in `/etc/batohub/batohub.conf` changes that: a mismatch then refuses to open the interface, and the operator rebuilds the manifest deliberately with `BaToHub --rebuild-integrity`.

### File Permissions

- Configuration and state files: mode 0600.
- `/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub`: mode 0750, owner root.
- Private keys: mode 0600, never printed, never logged.
- Backup archives and checksums: mode 0600.

### Update Verification

The self-update and the installer download a pinned release, never the `main` branch:

1. The newest published release tag is resolved through the GitHub API over HTTPS.
2. The release asset and its `manifest.json` are downloaded over HTTPS with certificate validation (`--proto '=https' --tlsv1.2 --fail`). Release asset URLs answer with a redirect to the object store, so the downloads follow redirects and are restricted to HTTPS on the redirect as well (`--location --proto-redir '=https'`); a download that silently fetched nothing is refused rather than treated as complete.
3. The asset SHA-256 is verified against the published `.sha256` sidecar. When the sidecar is unavailable, the SHA-256 recorded in `manifest.json` is used instead. When neither is available the download is refused.
4. Nothing is extracted before verification passes.

When a release asset is unavailable, both the installer and the self-update can fall back to the tagged source archive of the same tag. No checksum is published for that archive, so the fallback is refused unless the operator sets `BATOHUB_ALLOW_UNVERIFIED_FALLBACK=1`; the attempt fails with an error instead of installing an unverified tree.

Protected paths are never overwritten by an update: `/etc/batohub/batohub.conf`, `/etc/batohub/panel.conf`, `/var/lib/batohub`, `/var/log/batohub`, and every path listed in `USER_MANAGED_PATHS`. A snapshot of the installation tree is taken before files are replaced, and the previous tree is restored when post-update verification fails.

### What BaToHub Does Not Do

- BaToHub does not prevent a root user from modifying files on the same server.
- BaToHub does not review the code of the official panel installers it downloads and executes. Those installers are executed as supplied by their authors.
- BaToHub does not audit acme.sh.
- BaToHub does not make outbound calls except the downloads the operator requests: the release assets during install or update, the ACME API during certificate issuance, and a public IP lookup for the status view.
- BaToHub has not undergone an independent security audit or a penetration test.

## Verification Performed Before Release

Every release is verified before publication:

- `scripts/checks.sh` passes: shell syntax, shellcheck, shfmt formatting, JSON metadata, the panel and tool interfaces, version consistency, the release manifest, the release body, the git history, documentation presence, and text hygiene. The history check fails the build when any commit message carries a co-author trailer or names a development tool.
- `scripts/build-release.sh` builds the archive from the files git tracks, so an untracked or unreviewed file cannot reach a release, then verifies every archive member against `manifest.json` and the archive against its `.sha256` sidecar. The release job stops when either check fails.
- `scripts/verify-install.sh` passes: an isolated install that exercises the documented commands, the panel interface for all five panels, template apply, backup, restore, panel selection, and uninstall.
- `scripts/container-verify.sh` passes against `ubuntu:22.04` and `debian:12`: installation into a clean distribution userland, followed by the documented commands, tamper detection, and uninstall. The pipeline runs these checks in CI and on every release, and their logs are attached to workflow runs as artifacts named `container-verify-ubuntu-2204` and `container-verify-debian-12`.

Publication is followed by an installation from the published release assets into a clean Ubuntu 22.04 userland (`BATOHUB_VERIFY_SOURCE=release`). That is the download path the documented one-liner takes, so a defect in it makes the workflow that published the release fail instead of passing unnoticed.

These checks are structural and functional verification of BaToHub itself. They are not a behavioral test of any panel against a live upstream installation.

## Known Residuals

- Before v0.0.4 the git history contained two commits whose messages carried a
  co-author trailer naming a third-party development tool, and one commit
  message that referred to that tool. Those commits were ancestors of every tag
  up to v0.0.3. In v0.0.4 the history was rewritten to remove those lines, and
  the tags v0.0.1, v0.0.2 and v0.0.3 were moved onto the rewritten history.
  Commit identifiers recorded before the rewrite, in old clones, mirror caches
  or third-party references, no longer resolve. No commit, tag message or file
  in the repository contains such a trailer, and `scripts/checks.sh` fails when
  one is introduced. This residual is closed.

## Known Limitations

- The update mechanism trusts the configured GitHub repository over HTTPS. An attacker who controls that repository, or the account that publishes its releases, can publish a different tree. Verifying the SHA-256 against the release assets narrows this to whoever can publish a release; it does not remove the trust.
- Release archives are signed with GPG only when a `SIGNING_KEY` secret is configured. When no key is configured, the release carries SHA-256 checksums only, and no signature is claimed anywhere.
- Panel-specific correctness is verified structurally (interface functions, declared paths, version reporting). It is not verified behaviorally against live upstream panel installations as part of the release pipeline.
- Restore validation rejects absolute paths, parent traversal, undeclared members, paths the metadata does not declare, and links whose location or target leaves the BaToHub destination roots. Link members are read from the archive structure, and an archive whose links cannot be read is refused instead of being restored unverified. Both refusals are exercised with crafted archives by `scripts/verify-install.sh`. It cannot protect against an attacker who can already write to the BaToHub state directory.
- A backup archive contains panel configuration, which can include secrets. The archives are mode 0600 and owned by root, and they are not encrypted.

## No Bug Bounty

There is no bug bounty program at this time.
