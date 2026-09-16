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

### Panel API Credentials

Every call BaToHub makes to a panel API carries its credential inside a curl configuration file, not on a command line, so the credential does not appear in the process list of a shared server. The configuration file is created at mode 0600 and removed when the command finishes. A credential is never written to a log and never included in an error message; a failed request is reported with its status code and without the URL. Panel session cookies are kept in a cookie jar at mode 0600 that is removed on exit. A panel that rejects a credential stops the operation before any local record is written, and the refusal is logged without the credential.

### Node Records

One file per node holds the connection details the operator entered, under `${STATE_DIR}/nodes/` with mode 0600 and owner root:root. BaToHub stores no credential in that file: the panel API credential lives in the panel configuration and is read at the time of the call. Deregistration addresses the identifier the panel assigned, removes the local record, and writes nothing on the remote machine.

### Telegram Bot Model

The bot runs as its own service and maps each Telegram user id to a BaToHub account, so every command it runs passes the same permission gate as the interactive interface. The properties that matter:

- A user id that is not listed is refused and receives no reply. The refusal is recorded in `${LOG_DIR}/telegram-bot.log` with the user id and the reason. Silence is deliberate: a reply would confirm to anyone who reaches the bot that the endpoint belongs to a BaToHub instance.
- The allowed chat list is either a chat id or a `user id:chat id` pair. The paired form keeps a listed user out of the chat of another listed user.
- A listed user whose account does not exist is refused, and the missing account is recorded.
- Every command is recorded with the Telegram user id, the chat id, the BaToHub account and the command name. The bot token is never written to a log, and a command that fails records the failure without the message body.
- The bot never sends a configuration file, a credential, a private key or a token. A backup it sends is encrypted with the configured password, or is marked in its caption as unencrypted.
- The polling offset is stored at mode 0600 so a restart does not repeat a command that was already handled.

### Admin Role Model

- Accounts live in `${CONFIG_DIR}/admins.conf`, mode 0600, owner root:root, and store a hash produced by `openssl passwd`, never a password.
- A password that is supplied to the account commands is read from standard input or the prompt, not from an argument, so it does not reach the process list.
- The permission is checked when the menu is built and again inside the section that performs the action, so a hidden entry is not the only gate. The bot and the command line go through the same check.
- Every administrative action is appended to `${LOG_DIR}/admins.log` with the account, the action and the time. No password and no hash is written to a log.
- The account `root` is built in, holds every permission and cannot be removed.

### Alert Delivery Model

- Alert credentials (the Telegram token, the SMTP password and the webhook URL) live in `${CONFIG_DIR}/alerts.conf`, mode 0600, owner root:root. They are read at delivery time, never logged and never printed.
- No alert is enabled when the configuration file is created, and an alert with no entry in the file is off, so a release cannot start delivering on its own.
- Delivery to a webhook uses HTTPS with certificate validation, and the credential is carried in the request, not in a URL that a log would record.
- A failed delivery is logged with the channel name and the alert is not marked as delivered, so the condition is reported again on the next run instead of being lost.

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
- `scripts/verify-install.sh` passes: an isolated install that exercises the documented commands, the panel interface for all five panels, template apply, backup, restore, restore path validation against crafted hostile archives, panel selection, the v0.0.5 command surface, and uninstall.
- `scripts/integration-test.sh` passes: local HTTP services implement the endpoints each panel declares for its API plus the Bot API methods the delivery and the bot use, and the documented commands are driven against them. Authentication, request bodies, response parsing, error handling, state files and their permissions, node registration and deregistration, version listing, migration, backup delivery, alerts, accounts and the management bot are exercised end to end. The panels themselves are not installed: a panel installation needs a container or a machine of its own. What is verified is the BaToHub side of every call against the contract each panel publishes.
- `scripts/container-verify.sh` passes against `ubuntu:22.04` and `debian:12`: installation into a clean distribution userland, followed by the documented commands, tamper detection, and uninstall. The pipeline runs these checks in CI and on every release, and their logs are attached to workflow runs as artifacts named `container-verify-ubuntu-2204` and `container-verify-debian-12`.

Publication is followed by an installation from the published release assets into a clean Ubuntu 22.04 userland (`BATOHUB_VERIFY_SOURCE=release`). That is the download path the documented one-liner takes, so a defect in it makes the workflow that published the release fail instead of passing unnoticed.

These checks are structural and functional verification of BaToHub itself. They are not a behavioral test of any panel against a live upstream installation.

## Integration Test Results

`scripts/integration-test.sh` runs against service doubles, so its results describe the BaToHub side of every call. The outcome of the v0.0.5 run:

| Area | Verified |
| --- | --- |
| Service doubles | The panel service answers a credential check and the Telegram service answers `getMe` |
| Node management | Registration through the panel API, the record and its mode 0600, the identifier the panel returned, listing, status, restart, logs, refusal of an invalid address, refusal of a duplicate, refusal of a rejected password and of a rejected token with no record left behind, and deregistration |
| Migration | The published pairs, a preview that reads the source, a run that creates every source account at the destination and sends no write to the source |
| Backup delivery | Configuration reporting, a delivery test, a real archive created and uploaded, the ledger entry, and the token absent from every log |
| Alerts | The alert types, an alert nobody enabled delivering nothing, an enabled alert reaching the chat with its configured threshold, and the cooldown suppressing a repeat |
| Accounts | Creation, listing, the read-only role denied `panels.install` and allowed `panels.view`, the built-in account that cannot be removed, the published permission table, the file mode and the absence of a clear-text password |
| Reports | The report names, a per-account traffic report and a user count report rendered on screen, a CSV export written with mode 0600, the export listed and rotated |
| Server tools | The firewall, BBR, limits and time states reported without changing the system |
| Certificates | Name registration for two purposes, the panel configuration file mode, the reported status, refusal to revoke an unregistered name, and unregistration |
| Docker | A panel detected as a container, its status and log read through the runtime, and a panel without a runtime reported as native |
| Management bot | Configuration reporting, an authorised account, an unlisted account refused and left without a reply, one polling round that dispatches every queued command, the panel list arriving whole, and the refusal recorded |
| Secrets | No BaToHub log holds the bot token, and the node, delivery, bot and account files are all mode 0600 |

Two defects were found by this suite before the release and fixed in it: the inline program that parses a Telegram update was altered by the shell before Python received it, so no bot command was ever dispatched, and a multi-line form value was truncated by the transport, so a multi-line reply arrived as its first line. Both are covered by the suite now, and `scripts/checks_inline.py` fails the build when an inline program carries a single quote that the shell would consume. A third defect was found by the restore path validation added in the same release: two validations never ran, because a link scan depended on a padded column format and a declared-path loop read one line fewer than it needed to. Both were fixed and are exercised with crafted archives.

What the suite does not cover: the panels are not installed, so a panel's own installer, its service manager behaviour and its protocol handling are not exercised. A live panel installation remains necessary for that, and it is listed as a limitation.

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
