# BaToHub Documentation

## Table of Contents

- [1. Introduction](#1-introduction)
- [2. Requirements](#2-requirements)
- [3. Installation](#3-installation)
- [4. First Run](#4-first-run)
- [5. Panel Management](#5-panel-management)
- [6. Tools](#6-tools)
- [7. SSL](#7-ssl)
- [8. Subscription Templates](#8-subscription-templates)
- [9. Backup, Restore, Import](#9-backup-restore-import)
- [10. Self-Update](#10-self-update)
- [11. Security](#11-security)
- [12. Logging and Troubleshooting](#12-logging-and-troubleshooting)
- [13. Configuration Reference](#13-configuration-reference)
- [14. Command Reference](#14-command-reference)
- [15. FAQ](#15-faq)

## 1. Introduction

### 1.1 What BaToHub Is

BaToHub is a server management hub written in Bash. It runs on a Linux server as one command, `BaToHub`, and manages VPN and proxy panels and tools through a text interface and a command line interface. Each panel is a module under `panels/` that declares its own metadata, install paths, service name, SSL method, template method and update method. BaToHub discovers modules from the filesystem, manages one panel at a time, and keeps everything it owns under a central directory.

### 1.2 What BaToHub Is Not

- BaToHub is not a panel. It does not serve proxy protocols and does not manage users or inbounds. It manages the server-side operations around a panel.
- BaToHub is not an installer replacement. Panel installation and panel updates run each panel's official installer or updater; BaToHub does not reimplement them.
- BaToHub is not a monitoring system and does not collect or send telemetry.
- BaToHub is not a licensing product. It has no paid tier, no license enforcement, and no outbound call to any licensing server.

### 1.3 Supported Panels

| Name | Description | Install Path | Service Name | Default Port | Notes |
| --- | --- | --- | --- | --- | --- |
| Rebecca | Go binary or Docker Compose panel | `/opt/rebecca` | `rebecca` | 8000 | Configuration in `/opt/rebecca/.env` |
| Marzban | Python and React panel | `/opt/marzban` | `marzban` | 8000 | Template paths read from `.env` |
| PasarGuard | Python panel | `/opt/pasarguard` | `pasarguard` | 8000 | Template paths read from `.env` |
| 3X-UI | Sanaei web panel | `/usr/local/x-ui` | `x-ui` | 2053 | Database in `/etc/x-ui` |
| VPN-UI | Fork of 3X-UI, managed independently | `/opt/vpn-ui` | `vpn-ui` | 2053 | Supports bare-IP certificates |

### 1.4 Supported Tools

| Name | Description | Requirements | Notes |
| --- | --- | --- | --- |
| Foxima | PHP management interface for panel families | Docker, curl, wget, unzip | Drives the official installer, which deploys a Docker Compose stack and owns its configuration; BaToHub never writes the Foxima configuration and never removes the stack, its volumes or its data |

## 2. Requirements

### 2.1 Operating Systems

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Debian 12

Other distributions are not tested. The installer skips package installation on systems that are not Ubuntu or Debian and requires the dependencies to be present.

### 2.2 Dependencies

Required: `curl`, `tar`, `gzip`, `python3`, `openssl`.

Installed automatically by the installer on Ubuntu and Debian when missing, together with `ca-certificates`, `rsync` and `util-linux` (for `flock`): `curl`, `tar`, `gzip`, `python3`, `openssl`.

Optional but recommended: `rsync`, `flock` (in `util-linux`), `unzip` (release asset extraction; the installer falls back to python3 zipfile), `git` (not required).

`acme.sh` is required only when a certificate is issued through BaToHub. `systemd` is used when present for service status and restarts; its absence is detected and reported.

### 2.3 Disk and Memory

BaToHub itself needs less than 20 MB in `/opt/batohub` and a few MB in `/var/lib/batohub`. Backup archives grow with the size of the panel data directories they include. BaToHub runs comfortably in 128 MB of RAM; the panels it manages have their own requirements.

### 2.4 Network

- Outbound HTTPS to `github.com` and `api.github.com` for installation and self-update.
- Outbound HTTPS to `api.github.com` when a version list is requested. The list is the release list of that panel's or tool's own repository, so it reflects what its authors published and is subject to that API's rate limits.
- Outbound HTTPS to the ACME API when a certificate is issued.
- Outbound HTTPS to a public IP lookup service for the status view.
- Inbound TCP 80 during HTTP-01 certificate validation, and the panel's own ports.

## 3. Installation

### 3.1 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

This pipes the installer from the `main` branch of the repository. The installer itself never installs from `main`: it resolves the newest published release tag, downloads that release asset, verifies its SHA-256 against the published `.sha256` sidecar (or the manifest entry when the sidecar is missing), and installs from that pinned source.

The installer requires root. On Ubuntu and Debian it installs missing dependencies first. It then copies the release into `/opt/batohub`, creates `/etc/batohub`, installs the global command, validates every panel and tool interface, and writes the integrity manifest.

Every step is logged to `/var/log/batohub/install.log` with a timestamp.

### 3.2 Manual Install

```bash
git clone https://github.com/isAsli/BaTo-Hub.git
cd BaTo-Hub
sudo bash install.sh
```

When run from a checkout, the installer installs from that tree and does not download anything.

### 3.3 Unattended Install

The installer reads these environment variables and takes no interactive input at any point:

```bash
sudo BATOHUB_RELEASE_TAG=v0.0.4 INSTALL_DIR=/opt/batohub CONFIG_DIR=/etc/batohub \
  GLOBAL_CMD_NAME=/usr/local/bin/BaToHub bash install.sh
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `BATOHUB_RELEASE_TAG` | newest published release | The release tag to install |
| `BATOHUB_SOURCE_DIR` | unset | Install from this tree instead of downloading |
| `BATOHUB_ALLOW_UNVERIFIED_FALLBACK` | `0` | `1` allows the tagged source archive, which has no published checksum, to be used when no release asset is available |
| `INSTALL_DIR` | `/opt/batohub` | Program directory |
| `CONFIG_DIR` | `/etc/batohub` | Configuration directory |
| `STATE_DIR` | `/var/lib/batohub` | State directory |
| `LOG_DIR` | `/var/log/batohub` | Log directory |
| `GLOBAL_CMD_NAME` | `/usr/local/bin/BaToHub` | Path of the global command |

### 3.4 Post-Install Verification

| Command | What it confirms |
| --- | --- |
| `BaToHub --version` | The installed version, read from `/opt/batohub/VERSION` |
| `BaToHub --validate` | Every shipped panel and tool loads and exports the required functions |
| `BaToHub --check` | The files on disk match the integrity manifest |
| `BaToHub --status` | Panel state, panel version, service name and certificate directory |
| `BaToHub --detect` | Panels found on this server |

### 3.5 File Layout

```
/opt/batohub/              program files (installed by the installer)
  bin/                     entry point and uninstaller
  core/                    menu, loader, backup, tools, self-update
  lib/                     shared helper libraries
  panels/<name>/           one module per panel
  tools/<name>/            one module per tool
  security/                integrity manifest logic
  templates/subscription/  shared subscription template
  config/                  packaged copy of batohub.conf
  VERSION                  release version

/etc/batohub/              configuration and integrity manifest
/var/lib/batohub/          state, locks, certificates, tools, backups
/var/log/batohub/          batohub.log, install.log, update.log, versions.log
/usr/local/bin/BaToHub     symlink to /opt/batohub/bin/batohub
```

### 3.6 Re-Running the Installer

The installer is idempotent. On an installed server it preserves `/etc/batohub/batohub.conf` and `/etc/batohub/panel.conf`, snapshots the existing program directory before replacing it, restores that snapshot when any step fails, and removes the snapshot after complete success.

## 4. First Run

### 4.1 Panel Detection

On the first run BaToHub looks for supported panels. Detection checks, in order: the panel's install path from `panel.json`, the systemd unit name, and the default port. A panel is reported as detected when any check matches.

### 4.2 Panel Selection

When exactly one panel is detected, BaToHub asks you to confirm it. When several are detected, it shows a selection list. The confirmed choice is written to `/etc/batohub/panel.conf` with mode 0600 and the panel menu opens.

### 4.3 If No Panel Is Found

BaToHub lists the supported panels and offers to install one. If you decline, it opens a reduced menu with panel installation, tools, settings, self-update and the integrity check. Nothing else is configured.

### 4.4 If a Non-Supported Panel Is Found

A panel outside the supported list is reported as not compatible. BaToHub does not guess at unknown layouts. Requests for additional panels go through the contact handle in the README.

### 4.5 Switching Panels

`Settings` in the menu, or `BaToHub --select-panel NAME`, rewrites the `PANEL` key in `panel.conf`. The previous panel is not stopped, modified or removed; only BaToHub's focus changes.

## 5. Panel Management

Every panel module exposes the same interface, so each panel supports the same operations: detect, version, available versions, install, install a chosen version, uninstall, SSL issue/renew/status/remove, template apply/remove/status, update, logs, and a menu.

### 5.1 Rebecca

Rebecca is distributed as a Go binary under `/opt/rebecca`, or as a Docker Compose stack in the same directory. BaToHub reads the panel version from the `rebecca-cli` binary, checks the service state, and runs the official installer for install and update. Certificates are issued with acme.sh into `/var/lib/batohub/panels/rebecca/ssl/<target>/`; when `/opt/rebecca/.env` already declares certificate options, those keys are updated, otherwise the paths are printed for manual configuration.

### 5.2 Marzban

Marzban is a Python and React panel installed under `/opt/marzban` by the official Marzban scripts. Install and update run `marzban.sh install` and `marzban.sh upgrade` from the official script source. Subscription templates follow the `CUSTOM_TEMPLATES_DIRECTORY` and `SUBSCRIPTION_PAGE_TEMPLATE` values read from `/opt/marzban/.env`. Certificate options in `.env` (uvicorn cert and key) are updated when already present.

### 5.3 PasarGuard

PasarGuard is installed under `/opt/pasarguard` by the official PasarGuard scripts. Install and update run the official `pasarguard.sh` script. Template handling matches the Marzban family (`CUSTOM_TEMPLATES_DIRECTORY` with `SUBSCRIPTION_PAGE_TEMPLATE`), and existing certificate options in `.env` are updated in place.

### 5.4 3X-UI

3X-UI is installed under `/usr/local/x-ui` with its database in `/etc/x-ui` by the official installer. The `x-ui` CLI is used for version reporting and for certificate registration, and only when the installed CLI reports support for the certificate options. Subscription content is served by the panel's own web settings, so BaToHub stages the template in its state storage and does not edit the panel database.

### 5.5 VPN-UI

VPN-UI descends from the same code base as 3X-UI but is a separate installation under `/opt/vpn-ui` with its own `vpn-ui` service and its own deployment script. BaToHub manages it independently and never assumes 3X-UI paths. VPN-UI supports certificates for a bare address (`supports_bare_ip_ssl`), so `ssl-issue` accepts an IPv4 address where other panels require a domain.

### 5.6 Per-Panel Menu Reference

| Menu entry | Action |
| --- | --- |
| SSL management | Issue, renew, inspect, or remove certificates for this panel |
| Subscription template | Apply, inspect, or remove the BaToHub template for this panel |
| Panel status | State, version, service unit, install path, port |
| Panel version | The installed version, the versions published by the panel's own repository, and the installation of a chosen version |
| Panel update | Offers the newest release and, where the installer supports it, a chosen version; runs the panel's official updater |
| Panel logs | Prints the panel log tail |
| Server information | Host summary, resources, network, services, BaToHub log |
| Tools | The tools menu (Foxima) |
| Backup / Restore / Import backup | The backup flows described in section 9 |
| Settings | Panel switch and configuration files |
| Update BaToHub | Self-update, described in section 10 |
| Integrity check | Verify or rebuild the manifest, validate interfaces |
| Uninstall BaToHub | Removes BaToHub, keeps panels and their data |

### 5.7 Panel Version Detection and Selection

BaToHub reads the versions a panel offers from the release list of that panel's own repository. Nothing is hard-coded, so a release published by the panel's authors is selectable without changing BaToHub.

When a version is selected, BaToHub:

1. Reads the version that is installed now, and prints it before the operation.
2. Lists the newest stable releases from the panel's repository, marks the newest one as the default, and offers the development channel when the panel's installer declares one.
3. Runs the panel's own official installer with the version argument that installer documents. BaToHub does not reimplement the installation and passes no credentials to it.
4. Reads the installed version back and compares it with the requested one. A difference in formatting is reported instead of being accepted silently.
5. Records the change with a timestamp in `/var/log/batohub/versions.log` and in the main log. Only versions and outcomes are recorded.

| Panel | Version argument of the official installer | Scope | Development channel |
| --- | --- | --- | --- |
| Rebecca | `install --version <tag>`, and `update --version <tag>` on an installed panel | Install and update | `--dev` |
| Marzban | `install --version <tag>` | Install | `--dev` |
| PasarGuard | `install --version <tag>` | Install | `--dev`, `--pre-release` |
| 3X-UI | The release tag as the first positional argument | Install | `dev` |
| VPN-UI | None | Not supported | None |

VPN-UI is the exception: its official deployment script resolves the newest release itself and accepts no version argument. BaToHub reports its published versions for information and refuses a pinned install instead of ignoring the request. An already installed panel is moved between versions by the same rule: where the panel's updater accepts a version, that is used; where it does not, the panel's install path is used, and the panel's own data directories are left in place.

## 6. Tools

### 6.1 Foxima

Foxima is a PHP management interface that drives several panel families. Its official installer deploys a Docker Compose stack, installs Docker when it is missing, writes the configuration, starts the stack and installs its own management command. The installer decides the project directory itself, so BaToHub detects that directory after the installation and records it rather than choosing one.

Foxima is not a panel. It keeps its own layout, its own configuration and its own management command, and BaToHub assumes none of the panel conventions for it.

What the integration does:

1. Checks the commands the official installer needs: `curl` to fetch the installer, and `wget` and `unzip` to fetch and unpack a release. A missing command is reported before anything is downloaded. Docker is reported when it is absent; the official installer installs it.
2. Offers the published releases of the Foxima repository and the rolling build, with the newest stable release as the default, and installs the chosen one through the official installer's own version argument (`-v <tag>`, `-beta`).
3. Records the project directory in `/var/lib/batohub/tools/foxima/install.path` and records the version change in `/var/log/batohub/versions.log`.
4. Reads the installed version from the Foxima configuration key the installer writes, and falls back to a `version` file in the project directory.
5. Reports status from the Compose stack, and prints the installer log, the application log directory and the stack log.
6. Shows where the configuration lives and which setting names it holds, grouped into payment, panel and general settings. Values are never printed, because the file holds database passwords and bot tokens.
7. Updates through the official management command the installer installs. That command selects the version itself and owns the configuration and the data volumes, so BaToHub does not reimplement it and does not replace the stack.

What the integration does not do:

- It does not write the Foxima configuration. The installer and the installed interface own that file.
- It does not remove the stack, its Docker volumes, its configuration or its data. The removal entry clears only the record BaToHub wrote, after an explicit confirmation, and names the command that owns the installation.
- It does not treat Foxima as a panel and does not assume any other project's behaviour for it.

The tool menu entries are: detect the installation, install, update, status, logs, configure, clear the BaToHub record, and support contact. The support contact is read from the shipped documentation at run time, because source files carry no contact handle.

### 6.2 Adding a New Tool

A tool is a directory under `tools/` with `tool.json`, `module.sh`, and the `install/` and `menu/` sub-modules. Required functions: `tool_detect`, `tool_version`, `tool_status`, `tool_install`, `tool_update`, `tool_logs`, `tool_configure`, `tool_uninstall`, `tool_menu`. Optional functions: `tool_available_versions` and `tool_install_version`, for a tool whose installer accepts a version. `tool.json` declares at least `source_repo`, `supports_version_pinning`, `version_pin_scope` and `dev_channel_argument`. The loader discovers the directory automatically; run `BaToHub --validate` after adding one.

## 7. SSL

### 7.1 Per-Panel SSL Issuance

Certificates are issued with acme.sh in standalone HTTP-01 mode and stored per panel under `/var/lib/batohub/panels/<panel>/ssl/<target>/`, with `fullchain.pem` (0644) and `privkey.pem` (0600). A marker file records which panel owns the directory; BaToHub refuses to touch a certificate directory owned by another panel. Port 80 must be free; the check names the current listener when it is not.

### 7.2 Certificate Renewal

`ssl-renew` renews every BaToHub-managed certificate for the selected panel through acme.sh. The per-certificate reload command registered at issuance performs the panel restart.

### 7.3 Bare-IP SSL for VPN-UI

When `panel.json` declares `supports_bare_ip_ssl: true`, `ssl-issue` accepts an IPv4 address as the target and issues a certificate for it. Panels that do not declare it require a domain name, and an IP address is refused with an explanation.

### 7.4 Self-Signed Certificates

A self-signed certificate can be generated for a target where ACME validation is not possible. The certificate is written to the same per-panel layout and marked clearly as untrusted, for testing only.

### 7.5 Troubleshooting SSL

| Symptom | What to check |
| --- | --- |
| `Port 80 is already in use` | The message names the listener; stop it or use DNS-01 outside BaToHub |
| `certificate issuance failed` | The A record of the domain, port 80 reachability, and the acme.sh output in the log |
| DNS mismatch warning | The record does not point at this server; issuance continues only after confirmation |
| `No existing certificate option was found` | The panel configuration declares no certificate key; BaToHub prints the paths to configure |

## 8. Subscription Templates

### 8.1 Per-Panel Templates

The subscription template ships once at `templates/subscription/index.html`. A panel may override it with `panels/<panel>/templates/subscription/index.html`, which takes precedence when it exists. This is an intentional single-source layout: the shared file serves every panel, and the override supports panel-specific markup.

### 8.2 Applying a Template

Marzban-family panels read `CUSTOM_TEMPLATES_DIRECTORY` and `SUBSCRIPTION_PAGE_TEMPLATE` from their `.env` and the template is installed at that resolved path. Panels that generate subscription pages from their own settings (3X-UI, VPN-UI) receive the template staged in BaToHub state storage; the panel database is never edited. The previous file is always copied to `${STATE_DIR}/templates-backup/` before replacement.

### 8.3 Removing a Template

`template-remove` removes the applied or staged template after confirmation and keeps a copy in the templates backup directory, so the removal is reversible.

### 8.4 Customization

Edit a copy of the shared template, then install it through the prompt path or place it as the panel override in `panels/<panel>/templates/subscription/index.html` before applying.

## 9. Backup, Restore, Import

### 9.1 What Is Included in a Backup

- `/etc/batohub` in full;
- `/var/lib/batohub` in full, excluding the backup directory itself;
- `/var/log/batohub` in full;
- the configuration and data paths declared by the selected panel in `panel.json`;
- the certificate and template directories BaToHub manages for that panel;
- a metadata file, `BaToHub-backup.meta`, recording the BaToHub version, the panel, the panel version, the timestamp and the list of paths.

### 9.2 Creating a Backup

`BaToHub --backup`, or the Backup menu. The archive is written as `${BACKUP_DIR}/<timestamp>.tar.gz` with a `.sha256` sidecar, mode 0600, owner root.

### 9.3 Restoring a Backup

`BaToHub --restore FILE`, or the Restore menu. The restore:

1. Verifies the SHA-256 sidecar.
2. Validates the metadata file itself, then every archive member: members must be relative, free of parent traversal, below the BaToHub destination roots (`/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub`), declared in the metadata, and symlinks must not point outside those roots. Any failure aborts the restore before anything is written.
3. Creates a safety backup of the current state.
4. Extracts into a temporary directory and copies the declared paths into place, mapping packaged defaults onto configured directories when the installation uses non-default paths.

### 9.4 Importing an External Backup

`BaToHub --import FILE` is available in the menu (Import backup). The archive is copied into the backup directory, a checksum is generated when the source has none, and the archive then goes through the same validation and transactional restore.

### 9.5 Rotation Policy

`BACKUP_KEEP` (default 5) newest archives are kept; older ones and their checksums are removed after a successful backup.

### 9.6 Security of Backup Files

Archives and checksums are mode 0600, owner root. A backup contains panel configuration, which can include secrets; the archives are not encrypted, so the storage location matters.

## 10. Self-Update

### 10.1 How the Update Works

1. The newest published release tag is resolved through the GitHub API over HTTPS.
2. The release asset `BaToHub-<version>.zip` and `manifest.json` are downloaded over HTTPS with certificate validation.
3. The asset SHA-256 is verified against the `.sha256` sidecar, or against the manifest entry when the sidecar is missing. An unverified download is refused.
4. The tree is extracted and checked with `bash -n` and an interface validation before anything is replaced.
5. A state backup and an installation snapshot are created first.
6. Files are synchronised, leaving protected paths untouched: `/etc/batohub/batohub.conf`, `/etc/batohub/panel.conf`, `/var/lib/batohub`, `/var/log/batohub`, and every path in `USER_MANAGED_PATHS`.
7. Interfaces are validated and the integrity manifest is rebuilt and verified.

Every step is logged to `/var/log/batohub/update.log` with a timestamp.

### 10.2 What Is Preserved

Operator configuration, panel selection, panel state, certificates, logs, backups, and declared user-managed paths. Panels and their data are never touched by a BaToHub update.

### 10.3 Rollback

When any verification after the file synchronisation fails, the previous tree is restored from the snapshot and the update reports the failure. The pre-update backup stays in the backup directory.

### 10.4 Manual Update

`BaToHub --update`, or `BaToHub --update --force` to downgrade intentionally. Downgrades are refused without `--force`.

## 11. Security

### 11.1 Integrity Manifest

`${CONFIG_DIR}/integrity.sha256` holds a SHA-256 entry for every shipped file. It is written atomically under `flock`, verified on demand, after every update, and at the start of an interactive session. A missing manifest is a hard failure.

A mismatch is reported and logged, and the interface still opens, so the operator keeps control. Set `INTEGRITY_HARD_FAIL="1"` in `/etc/batohub/batohub.conf` to make a mismatch refuse to open the interface instead; `BaToHub --rebuild-integrity` is then the deliberate way to accept the current files.

### 11.2 File Permissions

- `/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub`: mode 0750, owner root.
- `batohub.conf`, `panel.conf`, backup archives, private keys: mode 0600.
- Program files: 0755 for executables, read-only for the rest.

### 11.3 Secrets Handling

Passwords, tokens and keys are never logged and never appear on command lines. Private keys are written with mode 0600 and are never printed. Configuration edits through the menu use the operator's editor on a mode-0600 file.

### 11.4 Update Verification

Described in section 10.1: pinned release, HTTPS with certificate validation, SHA-256 against the sidecar or the manifest, refusal of unverified downloads.

The tagged source archive of the same tag carries no published checksum, so the fallback to it is refused unless `BATOHUB_ALLOW_UNVERIFIED_FALLBACK=1` is set. Without that setting the operation fails and nothing is replaced.

### 11.5 What BaToHub Does Not Do

- It does not prevent a root user from modifying files; the manifest detects and reports.
- It does not review official panel installers before running them.
- It does not audit acme.sh.
- It makes no outbound call other than the ones the operator requests: release downloads during install or update, the release list of a panel's own repository when a version list is requested, the ACME API when a certificate is issued, and a public IP lookup for the status view.
- It has not undergone an independent audit or penetration test.

### 11.6 Known Limitations

Listed in [SECURITY.md](SECURITY.md#known-limitations). The short form: the update path trusts the GitHub repository and release assets; signing is optional and off unless a key is configured; panel behavior is verified structurally, not against live upstream installs.

## 12. Logging and Troubleshooting

### 12.1 Log Locations

| File | Content |
| --- | --- |
| `/var/log/batohub/batohub.log` | Operations: actions, outcomes, warnings, errors |
| `/var/log/batohub/install.log` | Installer steps, downloads, verification results |
| `/var/log/batohub/update.log` | Self-update steps, verification results, rollback |
| `/var/log/batohub/versions.log` | Panel and tool version changes with timestamps: component, action, requested, before, after |

### 12.2 Log Rotation

BaToHub does not rotate its own logs. Use logrotate with a policy that fits the server; the files are append-only text owned by root.

### 12.3 Common Issues

| Symptom | What to check |
| --- | --- |
| `certificate issuance failed` | DNS A record, port 80 availability, acme.sh output in the log |
| `Port 80 is already in use` | The message names the current listener |
| `Service X is not registered with systemd` | The panel has no systemd unit; nothing was restarted |
| `integrity: manifest missing` | Run `BaToHub --rebuild-integrity` |
| `integrity: mismatched files detected` | `BaToHub --check` lists the differing files |
| A panel is not detected | Compare the path, systemd unit and port with `panel.json` |
| `SHA-256 verification failed` | The download is not trusted; check network integrity and re-run |
| `The remote version X is older` | Downgrades are refused; use `--force` only with intent |
| `does not support version pinning` | That panel's installer always installs the newest release; use the install or update action |
| `no verifiable release asset is available` | The release asset is missing and the tagged source archive has no checksum; set `BATOHUB_ALLOW_UNVERIFIED_FALLBACK=1` only if you accept an unverified tree |
| `INTEGRITY_HARD_FAIL is enabled` | `BaToHub --rebuild-integrity` after reviewing what changed |

### 12.4 How to Report a Bug

Send the report to **@DatPHP** with:

- the output of `BaToHub --version`, `BaToHub --status` and `BaToHub --check`;
- the panel name and version;
- the exact command that failed and its error message;
- the last lines of `/var/log/batohub/batohub.log`.

Keep private keys, passwords and tokens out of reports.

## 13. Configuration Reference

### 13.1 batohub.conf

`/etc/batohub/batohub.conf`, mode 0600, created by the installer, never overwritten by an update:

| Key | Default | Description |
| --- | --- | --- |
| `APP_NAME` | `BaToHub` | Project name shown in the interface |
| `APP_VERSION` | `0.0.4` | Version, kept in step with the `VERSION` file |
| `INSTALL_DIR` | `/opt/batohub` | Program files |
| `CONFIG_DIR` | `/etc/batohub` | Configuration and integrity manifest |
| `STATE_DIR` | `/var/lib/batohub` | Panel state, certificates, backups, locks |
| `LOG_DIR` | `/var/log/batohub` | Log files |
| `BACKUP_DIR` | `/var/lib/batohub/backups` | Backup archives |
| `BACKUP_KEEP` | `5` | Number of archives to keep |
| `GITHUB_REPO` | `isAsli/BaTo-Hub` | Repository used by self-update |
| `GITHUB_BRANCH` | `main` | Repository branch (metadata only; content comes from release tags) |
| `GLOBAL_CMD_NAME` | `/usr/local/bin/BaToHub` | Path of the global command |
| `USER_MANAGED_PATHS` | empty | Space separated paths the update never touches |
| `INTEGRITY_HARD_FAIL` | `0` | `1` makes a failed integrity check refuse to open the interface |

### 13.2 panel.conf

`/etc/batohub/panel.conf`, mode 0600, written by BaToHub:

| Key | Description |
| --- | --- |
| `PANEL` | Panel identifier, for example `rebecca` |
| `PANEL_PORT` | Port recorded for the panel at selection time |
| `PANEL_PATH` | Installation path recorded at selection time |
| `PANEL_DOMAIN` | Domain read from the panel configuration when one is present |
| `INSTALLED_AT` | Date and time the panel was selected |

### 13.3 Environment Variables

`INSTALL_DIR`, `CONFIG_DIR`, `STATE_DIR`, `LOG_DIR`, `BACKUP_DIR`, `BACKUP_KEEP`, `GLOBAL_CMD_NAME`, `GITHUB_REPO`, `GITHUB_BRANCH` and `INTEGRITY_HARD_FAIL` override the configuration file when set. The installer additionally reads `BATOHUB_RELEASE_TAG`, `BATOHUB_SOURCE_DIR` and `BATOHUB_ALLOW_UNVERIFIED_FALLBACK` (section 3.3). `SSL_ACME_BIN`, `FOXIMA_REPO_URL`, `FOXIMA_INSTALLER_URL`, `FOXIMA_PROJECT_DIR`, `FOXIMA_MANAGEMENT_CMD` and the per-panel `*_SCRIPT_URL` / `*_INSTALLER_URL` variables override the upstream sources and paths, which is useful for mirrors and relocated installations.

## 14. Command Reference

| Command | Description |
| --- | --- |
| `BaToHub` | Open the interactive interface |
| `BaToHub --menu` | Same as running with no arguments |
| `BaToHub --help` | Print the usage text |
| `BaToHub --version` | Print the version |
| `BaToHub --list-panels` | List the supported panels with state and version |
| `BaToHub --tools` | List the supported tools |
| `BaToHub --tool NAME CMD` | Run one tool command without the menu |
| `BaToHub --detect` | List the panels detected on this server |
| `BaToHub --status` | Print the status summary |
| `BaToHub --select-panel NAME` | Store the panel BaToHub manages |
| `BaToHub --panel NAME CMD` | Run one panel command without the menu |
| `BaToHub --backup` | Create a backup now |
| `BaToHub --restore FILE` | Restore a backup archive |
| `BaToHub --update` | Update BaToHub from the pinned release |
| `BaToHub --check` | Verify the integrity manifest |
| `BaToHub --rebuild-integrity` | Rebuild the integrity manifest and verify it |
| `BaToHub --validate` | Validate every panel and tool interface |
| `BaToHub --uninstall` | Remove BaToHub and keep panels and their data |

Panel commands accepted by `--panel NAME CMD`:

| Command | Description |
| --- | --- |
| `detect` | Report whether the panel is installed |
| `version` | Print the panel version |
| `status` | Print `running`, `stopped` or `not_installed` |
| `install` | Run the panel's official installer |
| `uninstall` | Remove BaToHub-managed changes for that panel only |
| `ssl-issue` | Issue a certificate for the panel |
| `ssl-renew` | Renew BaToHub-managed certificates for the panel |
| `ssl-status` | Print certificate details |
| `template-apply` | Apply or stage the subscription template |
| `template-status` | Print the template report for the panel |
| `template-remove` | Remove the BaToHub-managed template |
| `versions` | List the versions the panel's own repository publishes |
| `install-version` | Install the release given as the next argument, through the panel's official installer |
| `update` | Run the panel's official updater |
| `logs` | Print the panel log tail |

Tool commands accepted by `--tool NAME CMD`:

| Command | Description |
| --- | --- |
| `detect` | Report whether the tool is installed |
| `version` | Print the installed version |
| `versions` | List the versions the tool's own repository publishes, when the tool declares them |
| `status` | Print `running`, `stopped` or `not_installed` |
| `logs` | Print the log sources of the tool |
| `configure` | Show where the configuration lives and which settings it holds, without printing values |
| `install` | Run the tool's official installer |
| `install-version` | Install the release given as the next argument, through the tool's official installer |
| `update` | Run the tool's official updater |
| `uninstall` | Remove the changes BaToHub manages for that tool only |

## 15. FAQ

**Does BaToHub remove or reset my panel when I switch panels?**
No. Switching rewrites one key in `panel.conf`. The previous panel keeps running untouched.

**Does the uninstaller delete panel data?**
No. The uninstaller removes `/opt/batohub`, `/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub` and the global command link. Panels, their databases, their configuration and their certificates outside BaToHub state storage are never removed. Backup archives can be moved to `/var/backups/batohub-<timestamp>` instead of being deleted.

**Why does the installer refuse to continue with a checksum error?**
The downloaded release asset did not match its published SHA-256. Nothing was extracted and nothing was changed. Check network integrity and re-run.

**Can I install a specific version of BaToHub?**
Yes. Set `BATOHUB_RELEASE_TAG=v0.0.4` before running the installer (section 3.3).

**Can I install a specific version of a panel?**
Yes, through the panel's own installer. `Panel version` in the menu, or `BaToHub --panel NAME versions` followed by `BaToHub --panel NAME install-version <tag>`, lists the releases the panel publishes and installs the chosen one (section 5.7). VPN-UI is the exception: its deployment script accepts no version.

**Does BaToHub phone home?**
No. There is no telemetry and no licensing server. Outbound HTTPS happens only when you install, update, issue a certificate, request a panel version list, or open the status view.

**Can BaToHub manage more than one panel at a time?**
One panel is managed at a time. Switching changes the focus without modifying the previous panel.

**Is the release signed?**
Only when a signing key is configured in the release pipeline. Otherwise the release carries SHA-256 checksums and no signature is claimed. See [SECURITY.md](SECURITY.md).

**How do I add a panel or a tool?**
Create a module directory under `panels/` or `tools/` following the layout in sections 5 and 6.2, then run `BaToHub --validate`.
