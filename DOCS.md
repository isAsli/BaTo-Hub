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
- [13. Servers and Nodes](#13-servers-and-nodes)
- [14. Multiple Domains and Wildcard Certificates](#14-multiple-domains-and-wildcard-certificates)
- [15. Backup Delivery to Telegram](#15-backup-delivery-to-telegram)
- [16. Migration Between Panels](#16-migration-between-panels)
- [17. Server Tools](#17-server-tools)
- [18. Docker](#18-docker)
- [19. Alerts and Notifications](#19-alerts-and-notifications)
- [20. Admins and Roles](#20-admins-and-roles)
- [21. Reports](#21-reports)
- [22. Telegram Bot](#22-telegram-bot)
- [23. Configuration Reference](#23-configuration-reference)
- [24. Command Reference](#24-command-reference)
- [25. FAQ](#25-faq)

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

This section covers the certificate of a single panel name. Registering several names for one panel, wildcard certificates, DNS validation and revocation are covered in section 14.

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
2. Validates the metadata file itself, then every archive member: members must be relative, free of parent traversal, below the BaToHub destination roots (`/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub`), declared in the metadata, and symlinks or hard links must not point outside those roots. Link members are read from the archive structure rather than from the tar listing, and an archive whose links cannot be read is refused. Any failure aborts the restore before anything is written.
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

## 13. Servers and Nodes

A node is a remote server that a panel uses for its own workers, for example a Marzban node or a second worker for 3X-UI. BaToHub keeps the record of that node, makes the calls that register and deregister it through the panel's own API, and reports its state. It does not install anything on the remote machine and it never deletes data there.

### 13.1 What BaToHub Owns

| Item | Location | Notes |
| --- | --- | --- |
| Node record | `${STATE_DIR}/nodes/<panel>.<name>.conf` | Mode 0600, owner root:root, one key per line |
| Registration calls | The panel's own API, per `panel.json` | No remote shell and no agent |
| Operation log | `${LOG_DIR}/nodes.log` | One line per registration, restart and deregistration |

The record holds `NODE_PANEL`, `NODE_NAME`, `NODE_ROLE`, `NODE_HOST`, `NODE_PORT`, `NODE_TLS`, `NODE_FINGERPRINT`, `NODE_ADDED_AT` and, once the panel has answered, `NODE_REMOTE_ID`. The identifier is what a later restart or deregistration addresses, so it is recorded rather than the address alone.

### 13.2 Panel Credentials

`${CONFIG_DIR}/nodes.conf`, mode 0600, holds the endpoint and the credential of each panel:

| Key | Example | Description |
| --- | --- | --- |
| `NODES_API_BASE_<PANEL>` | `http://127.0.0.1:8000/marzban` | Base URL of the panel API |
| `NODES_API_TOKEN_<PANEL>` | | API token, used when the panel declares token authentication |
| `NODES_USER_<PANEL>` | `admin` | Administrator name, used when the panel declares session authentication |
| `NODES_PASSWORD_<PANEL>` | | Administrator password for that session |

`<PANEL>` is the panel identifier in upper case with a hyphen replaced by an underscore, for example `NODES_API_BASE_3X_UI`. The authentication mode of each panel (token, session, or session cookie) is declared by that panel's `panel.json`, so BaToHub never guesses it. Credentials are handed to the HTTP layer through a curl configuration file and never appear on a command line or in a log. A panel that rejects the credential stops the operation before any record is written.

### 13.3 Registering a Node

1. BaToHub validates the name, the role, the address and the port against the pattern the panel declares.
2. It refuses a node that is already recorded for that panel, and names the existing record.
3. It calls the panel's own add endpoint with the body the panel declares, including the role and the port.
4. The panel assigns the identifier. BaToHub reads it back from the response and stores it in the record.
5. It prints the node installer command taken from `node_installer_url` in `panel.json`, with the address, the port and the recorded fingerprint already filled in, so the remote side is prepared with the panel's own installer.
6. It appends the outcome to `${LOG_DIR}/nodes.log` and to the main log.

### 13.4 Node Commands

| Command | Description |
| --- | --- |
| `BaToHub --nodes list` | Every recorded node with its panel, address, state and registration time |
| `BaToHub --nodes panels` | The panels that declare node support |
| `BaToHub --nodes panel-list NAME` | The nodes the panel itself reports |
| `BaToHub --nodes show NAME NODE` | The record, the state read from the panel, and the recorded identifier |
| `BaToHub --nodes restart NAME NODE` | Restart through the panel API |
| `BaToHub --nodes logs NAME NODE` | Log tail from the panel API, or from `journalctl` for a local unit |
| `BaToHub --nodes bundle NAME NODE` | The connection information and installer command to run on the remote server |
| `BaToHub --nodes add NAME NODE ROLE HOST PORT [FINGERPRINT] [TLS]` | Register a node without the menu |
| `BaToHub --nodes remove NAME NODE` | Deregister the node and remove the local record |

### 13.5 Removing a Node

`--nodes remove` deregisters the node through the panel with the identifier in the record, then removes the local record. The remote machine is not touched: no file is deleted there and no service is stopped there. When the panel refuses the deregistration, the record is kept and the refusal is reported, so the two sides cannot silently disagree about which nodes exist.

### 13.6 Per-Panel Notes

| Panel | Role | Default node port | Notes |
| --- | --- | --- | --- |
| Rebecca | `node` | 62050 | Registered through the panel API; the installer command is the one the panel documents |
| Marzban | `node` | 62050 | Session authentication; the identifier the panel returns is recorded and used for restart |
| PasarGuard | `node` | 62050 | Registered through the panel API |
| 3X-UI | `node` | 62050 | Session cookie authentication |
| VPN-UI | `node` | 62050 | Managed under its own paths, independently of 3X-UI |

## 14. Multiple Domains and Wildcard Certificates

A panel can answer on more than one name: its administration domain, its subscription domain, and any further name an operator uses. Each name is registered per panel, so the certificate layout of one panel is never inferred from another's.

### 14.1 Purpose per Name

| Purpose | Meaning |
| --- | --- |
| `panel` | The name the administration interface is served on |
| `subscription` | The name subscription links are served on |
| `custom` | Any other name for the same panel |

The purpose is recorded with the name so `--ssl status` can report which names belong to the panel and which belong to subscriptions, and so a renewal can reload the right service.

### 14.2 Registration

`${CONFIG_DIR}/ssl/<panel>.conf`, mode 0600, holds one entry per line: the name, its purpose, the method used, the issuance time and the certificate fingerprint. A name is registered before a certificate is requested for it, and a name that belongs to another panel is refused rather than silently moved.

### 14.3 Method Selection

| Situation | Method |
| --- | --- |
| An ordinary name and free port 80 | `http-01` |
| A wildcard name such as `*.example.com` | `dns-01` |
| Validation not possible for the name | `self-signed`, clearly marked as untrusted and for testing |

A wildcard name cannot be validated over HTTP-01, so the entry switches to DNS-01 and needs the provider API in `${CONFIG_DIR}/ssl/dns.conf`, mode 0600. Provider credentials are exported into the `acme.sh` process environment from that file. They are never passed on a command line and never printed. When the provider is not configured, the wildcard entry is refused with an explanation instead of falling back to a method that cannot validate it.

### 14.4 Certificate Commands

| Command | Description |
| --- | --- |
| `BaToHub --ssl list` | Every registered name with its panel, purpose, method, issuance time and expiry |
| `BaToHub --ssl register PANEL NAME [PURPOSE]` | Register a name for a panel |
| `BaToHub --ssl unregister PANEL NAME` | Stop managing a name; the certificate files are kept |
| `BaToHub --ssl issue PANEL NAME` | Request a certificate for a registered name |
| `BaToHub --ssl renew PANEL` | Renew every certificate of that panel |
| `BaToHub --ssl status PANEL` | Reported state, method, remaining days and fingerprint |
| `BaToHub --ssl revoke PANEL NAME` | Revoke a certificate and record the revocation |

### 14.5 Renewal Hooks

At issuance BaToHub registers a reload command with `acme.sh` for that certificate, so a renewal restarts the service that serves it. The reload command is the panel restart path, which means a renewed certificate is in use after the renewal instead of only on disk.

### 14.6 Isolation and Logging

Two panels never share a certificate path. The certificate directory carries a marker naming the panel that owns it, and BaToHub refuses to touch a directory owned by another panel. Every issuance, renewal and revocation is appended to `${LOG_DIR}/ssl.log` with a timestamp, the name, the method and the outcome; no key material is written to the log.

## 15. Backup Delivery to Telegram

BaToHub can create a backup on a schedule and deliver the archive to a Telegram chat, so an archive exists off the server without a second service.

### 15.1 Configuration

`${CONFIG_DIR}/telegram.conf`, mode 0600, owner root:root:

| Key | Default | Description |
| --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` | empty | Token of the bot that delivers the archive |
| `TELEGRAM_CHAT_ID` | empty | Chat that receives the archive |
| `TELEGRAM_BACKUP_ENABLED` | `0` | `1` enables scheduled delivery |
| `TELEGRAM_BACKUP_SCHEDULE` | `daily` | `hourly`, `daily` or `weekly` |
| `TELEGRAM_BACKUP_KEEP_REMOTE` | `7` | How many delivered archives are kept in the chat |
| `TELEGRAM_MAX_UPLOAD_BYTES` | `45000000` | Size above which an archive is split before it is sent |

### 15.2 Schedule

`BaToHub --backup-deliver` writes a systemd timer when systemd is present and a cron entry otherwise. The timer runs `BaToHub --backup-deliver send`, which creates the archive, delivers it, records the result and then applies the local retention policy in `BACKUP_KEEP`. An hourly schedule runs at the start of the hour, daily at 03:30, weekly on Monday at 03:30.

### 15.3 What Is Delivered

1. The archive is created first. An archive that could not be created stops the delivery and nothing is sent.
2. An empty archive is never sent.
3. A large archive is split into parts below `TELEGRAM_MAX_UPLOAD_BYTES`, and every part is sent as a document with its index in the caption.
4. The delivery is confirmed from the API response. A response without a message identifier is treated as a failure and is reported as one.
5. The ledger `${BACKUP_DIR}/telegram-delivered`, mode 0600, records the archive name, the message identifier and the time, so what was delivered can be listed and compared with what is on disk.

The delivery states plainly whether an archive is encrypted. When `TELEGRAM_BOT_BACKUP_PASSWORD` is set in the bot configuration, the archive is encrypted before it leaves the server; when it is not set, the archive is sent unencrypted and the message says so.

### 15.4 Commands

| Command | Description |
| --- | --- |
| `BaToHub --backup-deliver status` | Configuration state, delivery state, schedule and retention |
| `BaToHub --backup-deliver test` | Send a test message and report whether it arrived |
| `BaToHub --backup-deliver send` | Create an archive and deliver it now |
| `BaToHub --backup-deliver ledger` | The archives that were delivered, with times and message identifiers |

### 15.5 Security of the Token

The token is read from the configuration file and passed to the HTTP layer through a curl configuration file, so it does not appear on a command line or in the process list. It is never written to a log and never included in an error message; a request that fails is reported with its status code and without the URL. The configuration file is created at mode 0600 and re-checked on every use.

## 16. Migration Between Panels

Migration reads accounts from one panel and creates them on another through the APIs of both. It never writes to the source and never removes anything.

### 16.1 Supported Pairs

| Source | Destination | Data |
| --- | --- | --- |
| Marzban | PasarGuard | Accounts |
| Marzban | Rebecca | Accounts |
| PasarGuard | Marzban | Accounts |
| PasarGuard | Rebecca | Accounts |
| Rebecca | Marzban | Accounts |
| 3X-UI | VPN-UI | Inbounds |
| VPN-UI | 3X-UI | Inbounds |

`BaToHub --migration pairs` prints the list the running release supports. A pair is offered only when both panels declare the endpoint that the direction needs, so a pair listed here is a pair the shipped code can actually perform.

### 16.2 Flow

1. The source panel is read through its own API: accounts, status, expiry, data limit and used traffic; for the 3X-UI family, inbounds with their protocol, port and settings.
2. The records are mapped to the destination format. A field the destination cannot hold is reported rather than dropped silently.
3. A preview is printed: how many accounts will be created, how many are skipped, and why.
4. The operator confirms.
5. Both panels are backed up before anything is written.
6. The destination is written through its own API.
7. The result is read back and compared with the preview.
8. Every account that could not be migrated is listed with the reason the destination gave.

### 16.3 Safety Rules

- The source panel receives no write of any kind. This is checked by the verification suite as well: after a migration, no creation request has been sent to the source.
- An account that already exists on the destination is not overwritten without an explicit confirmation for that account.
- Both panels are backed up before the write, and the backup paths are printed.
- When the migration stops partway, the accounts already created are listed with their identifiers and the accounts that were not created are listed as well, so the destination state is known instead of assumed.
- Every step is appended to the BaToHub log and to the migration output.

### 16.4 Commands

| Command | Description |
| --- | --- |
| `BaToHub --migration pairs` | The supported directions |
| `BaToHub --migration preview SRC DST` | Read the source and print what would be created, without writing |
| `BaToHub --migration run SRC DST` | Back up both panels, write the destination and verify the result |

### 16.5 Limits

Traffic history is not transferred: a panel reports totals, not a per-day series, so an account arrives at the destination with its limits and its used total, not with a breakdown. Subscription links are not copied, because each panel builds its own from its own domain and inbound settings; the destination creates its own links after the account exists.

## 17. Server Tools

`BaToHub --server` groups the operating system tasks that are usually done by hand on a fresh server. Every subcommand prints the current state before it changes anything, and prints what it will change before it changes it.

### 17.1 Firewall (UFW)

| Operation | Behaviour |
| --- | --- |
| Show the state and the rules | Printed as the system reports them, with the default policy |
| Open or close a port | The rule and its effect are printed before it is applied |
| Allow a port from one address | The rule is restricted to that address |
| Enable or disable the firewall | Existing rules are listed first; disabling requires a second confirmation |

An existing rule is not overwritten without confirmation. When disabling the firewall would affect the session that is running BaToHub, that is detected from the listening ports and reported before the change.

### 17.2 Fail2ban

| Operation | Behaviour |
| --- | --- |
| Status and jails | The service state and the configured jails are printed |
| Banned addresses | The current bans are listed per jail |
| Unban | One address is removed from one jail |
| Edit a jail | A drop-in under `/etc/fail2ban/jail.d/99-batohub.conf` is written, so the packaged configuration is not edited |
| Install and restart | The package is installed through the system package manager and the service is restarted |

### 17.3 BBR and TCP Tuning

| Operation | Behaviour |
| --- | --- |
| Status | Congestion control, queue discipline and the current values |
| Enable BBR | The kernel setting is written to `/etc/sysctl.d/99-batohub-bbr.conf` and applied |
| Apply the tuning profile | A documented set of TCP values is written to the same drop-in |
| Revert | The drop-in is removed and the kernel defaults are restored |

The current values are printed before and after a change, so a revert has a recorded starting point.

### 17.4 System Limits

| Operation | Behaviour |
| --- | --- |
| Show | File descriptor limit and connection tracking limit as they are now |
| Raise the file descriptor limit | Written to `/etc/security/limits.d/99-batohub.conf` |
| Raise the connection tracking limit | Written to the same drop-in and applied |

### 17.5 Time and NTP

| Operation | Behaviour |
| --- | --- |
| Status | Current time, time zone and synchronisation state |
| Set the time zone | Applied through `timedatectl` when it is available, otherwise written to `/etc/timezone` |
| Enable NTP | Synchronisation is enabled and the state is read back |

### 17.6 Commands

| Command | Description |
| --- | --- |
| `BaToHub --server firewall status` | Firewall state and rules |
| `BaToHub --server firewall allow-port PORT` | Open a port |
| `BaToHub --server firewall deny-port PORT` | Close a port |
| `BaToHub --server firewall allow-from PORT ADDRESS` | Allow a port from one address |
| `BaToHub --server firewall enable` / `disable` | Enable or disable the firewall |
| `BaToHub --server fail2ban status` / `jails` / `banned` | Service state, jails, current bans |
| `BaToHub --server fail2ban unban JAIL ADDRESS` | Remove one ban |
| `BaToHub --server fail2ban install` / `restart` | Install or restart the service |
| `BaToHub --server bbr status` / `enable` / `tuning` / `revert` | BBR and TCP tuning |
| `BaToHub --server limits show` / `nofile SOFT HARD` / `conntrack VALUE` | System limits |
| `BaToHub --server time status` / `timezone ZONE` / `ntp` | Time and synchronisation |

## 18. Docker

A panel may run in a container or directly on the host, and the two need different commands for status, logs, restart and update. BaToHub detects which one applies instead of assuming it.

### 18.1 Detection

Each `panel.json` declares `supports_docker` and, where it applies, `docker_container_name`. Detection looks at how the panel is present on this server: the panel's own directory for a Compose stack, and the container runtime when it is installed. A panel is never reported as a container because Docker happens to be installed, and never reported as native because Docker is absent.

### 18.2 Modes

| Mode | Meaning |
| --- | --- |
| `docker` | The panel runs in a container that was found on this server |
| `compose` | The panel runs from a Compose stack in its directory |
| `native` | The panel runs as a system service |
| `none` | The panel is not installed |

### 18.3 Operations

| Operation | Behaviour when the panel is a container |
| --- | --- |
| Status | Container state, image, started time and restart count |
| Logs | `docker logs` for that container, with the same tail the native path uses |
| Restart | The container is restarted, not the host service unit |
| Statistics | CPU, memory and network counters for that container |
| Image update | The declared image is pulled and the container is recreated, after the panel's data volumes are confirmed |

When the panel is native, every one of these operations uses the service unit and the panel's own log path, exactly as it did before Docker support existed.

### 18.4 Commands

| Command | Description |
| --- | --- |
| `BaToHub --container list` | Every panel with its mode and container state |
| `BaToHub --container mode PANEL` | The detected mode, with the evidence for it |
| `BaToHub --container status PANEL` | State, image and uptime |
| `BaToHub --container logs PANEL` | Log tail through the runtime or the service unit |
| `BaToHub --container restart PANEL` | Restart through the runtime or the service unit |
| `BaToHub --container stats PANEL` | Resource counters for the container, or the process for a native panel |
| `BaToHub --container update PANEL` | Update the panel image and recreate the container |

## 19. Alerts and Notifications

Alerts read the state BaToHub already keeps and deliver a message when a condition holds. No agent is installed and no telemetry is collected.

### 19.1 Alert Types

| Alert | Condition | Default threshold |
| --- | --- | --- |
| `panel_down` | The managed panel is not running | none |
| `node_offline` | A recorded node does not report a connected state | none |
| `ssl_expiring` | A certificate expires within the threshold | 14 days |
| `version_outdated` | The installed panel version differs from the newest published stable release | none |
| `disk_usage` | Disk usage of `/`, `/var` or `/opt` is at or above the threshold | 85 percent |
| `memory_usage` | Memory usage is at or above the threshold | 90 percent |
| `cpu_load` | Load per processor is at or above the threshold | 4 |
| `backup_stale` | The newest archive is older than the threshold | 48 hours |
| `update_failed` | The most recent recorded update outcome is a failure | none |

`version_outdated` is the only alert that makes an outbound request: it reads the release list of the panel's own repository. A panel whose repository cannot be read is reported as unknown and never as outdated.

### 19.2 Enabled State

No alert is enabled when the configuration file is created, and an alert with no entry in the file is off. Nothing is delivered until an operator enables a specific alert, and an alert added by a later release therefore stays silent until it is enabled deliberately. A run with a condition that holds and the alert disabled delivers nothing.

### 19.3 Thresholds and Cooldowns

Each alert has a threshold and a cooldown in seconds. The cooldown is recorded per alert in `${STATE_DIR}/alerts/<alert>.last`, so a condition that continues is not reported on every run. Memory and CPU alerts default to a cooldown of 900 seconds and the rest to 3600 seconds.

### 19.4 Delivery

| Channel | Configuration |
| --- | --- |
| Telegram | `TELEGRAM_BOT_TOKEN` in the Telegram configuration, or the same key in `alerts.conf` |
| Email | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_TO` |
| Webhook | `ALERT_WEBHOOK_URL`, called with a POST and a JSON body |

`${CONFIG_DIR}/alerts.conf` is mode 0600 and holds the credentials. They are never logged and never printed. When one channel fails, the failure is logged with the channel name and the next run tries again; a failed delivery does not mark the alert as delivered, so the condition is reported again rather than being lost.

### 19.5 Schedule

`BaToHub --alerts schedule` installs a systemd timer, or a cron entry when systemd is absent, which runs `BaToHub --alerts run` every fifteen minutes. `BaToHub --alerts unschedule` removes it. `--alerts check` evaluates the conditions without delivering anything, which is what the menu uses to show what currently holds.

### 19.6 Commands

| Command | Description |
| --- | --- |
| `BaToHub --alerts status` | Every alert with its enabled state, threshold, cooldown and last delivery |
| `BaToHub --alerts types` | The alert names this release supports |
| `BaToHub --alerts check` | Evaluate the conditions and print those that hold, without delivering |
| `BaToHub --alerts run` | Evaluate and deliver, honouring the cooldowns |
| `BaToHub --alerts enable NAME` / `disable NAME` | Turn one alert on or off |
| `BaToHub --alerts threshold NAME VALUE` | Set the threshold of one alert |
| `BaToHub --alerts schedule` / `unschedule` | Install or remove the timer |

## 20. Admins and Roles

BaToHub can be operated by more than one account, each with the permissions of its role. The permission is checked when the menu is built and again when the action runs, so a hidden entry is not the only protection.

### 20.1 Accounts

`${CONFIG_DIR}/admins.conf`, mode 0600, owner root:root, holds one entry per account: the name, the role and a hash of the password. Passwords are hashed with the system `openssl passwd`. The account `root` is built in, always holds the full role and cannot be removed. When no account is recorded, the operator is `root` with the full role, which is the state of an installation that never used this section.

### 20.2 Roles

| Role | Permissions |
| --- | --- |
| `full` | Every permission |
| `panel-manager` | Panels, templates, SSL, backups and migration; no server tools and no account management |
| `ssl-manager` | View and the certificate permissions |
| `backup-manager` | View and the backup permissions |
| `read-only` | View only: panels, servers and alerts |
| `custom` | The permissions chosen for that account |

### 20.3 Permissions

| Permission | Covers |
| --- | --- |
| `panels.view` | Listing panels and their state |
| `panels.install` | Installing a panel |
| `panels.update` | Updating a panel |
| `panels.uninstall` | Removing BaToHub-managed changes for a panel |
| `ssl.issue` | Requesting a certificate |
| `ssl.renew` | Renewing certificates |
| `ssl.revoke` | Revoking a certificate |
| `templates.apply` | Applying a subscription template |
| `templates.remove` | Removing a subscription template |
| `backup.create` | Creating a backup and delivering it |
| `backup.restore` | Restoring a backup |
| `backup.delete` | Deleting a backup archive |
| `servers.view` | Listing nodes |
| `servers.add` | Registering a node |
| `servers.remove` | Deregistering a node |
| `tools.run` | Running the server tools |
| `alerts.view` | Reading the alert state |
| `alerts.configure` | Changing thresholds, delivery and the schedule |
| `admins.manage` | Managing accounts and roles |
| `settings.edit` | Editing settings, the bot and the integrity state |
| `migration.run` | Running a migration |
| `update.run` | Updating BaToHub |

### 20.4 Enforcement

- The acting account is read from `BATOHUB_ADMIN` when it is set, and otherwise from the account that started the process.
- The main menu prints an entry only when the entry's permission is held, so a role is visible in the interface.
- Every section checks the permission again before it acts, so a hidden entry is not the only gate.
- Every action is appended to `${LOG_DIR}/admins.log` with the account, the action and the time. No password and no hash is written to any log.

### 20.5 Commands

| Command | Description |
| --- | --- |
| `BaToHub admin list` | The accounts with their roles |
| `BaToHub admin status [NAME]` | One account with its role and its permissions |
| `BaToHub admin permissions` | The permission names this release uses |
| `BaToHub admin roles` | The roles with the permissions of each |
| `BaToHub admin add NAME ROLE` | Create an account; the password is read from standard input |
| `BaToHub admin remove NAME` | Remove an account that is not `root` |
| `BaToHub admin passwd NAME` | Change a password |
| `BaToHub admin role NAME ROLE` | Change a role |
| `BaToHub admin check PERMISSION` | Report whether the acting account holds the permission; the exit status is 0 when it does |

## 21. Reports

Reports read the state BaToHub and the panels already hold and print it as a table, a CSV file or JSON.

### 21.1 Reports

| Report | Content |
| --- | --- |
| `panel_traffic` | Traffic per panel and the number of accounts behind it |
| `user_traffic` | Traffic per account on every panel that reports accounts |
| `user_counts` | Number of accounts per panel |
| `active_users` | Accounts whose status is active, with expiry |
| `expired_users` | Accounts that are expired, with expiry |
| `ssl_status` | Registered names, method, issuance time and remaining days |
| `backup_history` | Archives on disk with their sizes and times |
| `update_history` | Recorded update outcomes |
| `alert_history` | Alerts that were delivered, with the time |
| `admin_actions` | Recorded administrative actions, with the account and the time |

A panel that is not installed, or that does not report accounts, is left out of a report rather than shown as zero.

### 21.2 Formats

`screen` prints a padded table, `csv` prints a header line and one line per record, and `json` prints an array of objects keyed by the column names. The same rows are rendered in all three, so a value seen on screen is the value in the export.

### 21.3 Exports and Rotation

Exports are written to `${STATE_DIR}/reports/<report>-<timestamp>.<format>`, mode 0600, and the directory is kept at mode 0750. `REPORT_KEEP` sets how many exports are kept; a rotation removes the oldest exports first. Both an export and a rotation are recorded in the BaToHub log.

### 21.4 Commands

| Command | Description |
| --- | --- |
| `BaToHub --reports list` | The report names this release supports |
| `BaToHub --reports show NAME [screen|csv|json]` | Print one report |
| `BaToHub --reports export NAME [csv|json]` | Write one report to the export directory |
| `BaToHub --reports exports` | The exports on disk with their times and sizes |
| `BaToHub --reports rotate` | Apply the retention policy now |

## 22. Telegram Bot

BaToHub can be operated from Telegram by a bot that runs as its own service. The bot maps each Telegram user to a BaToHub account and runs every command through the same permission gate the interface uses.

### 22.1 Configuration

`${CONFIG_DIR}/telegram_bot.conf`, mode 0600, owner root:root:

| Key | Description |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | Token of the bot |
| `TELEGRAM_BOT_USERS` | Telegram user id to BaToHub account, as `123456789:root,987654321:ops` |
| `TELEGRAM_BOT_CHATS` | Allowed chats: either a chat id, or a pair `user id:chat id` that keeps one listed user out of the chat of another. Empty means every chat of a listed user |
| `TELEGRAM_BOT_BACKUP_PASSWORD` | Password used to encrypt a backup the bot sends; empty sends it unencrypted with a warning |
| `TELEGRAM_BOT_POLL_TIMEOUT` | Long polling timeout in seconds |

### 22.2 Commands

| Command | Action |
| --- | --- |
| `/start`, `/help` | Show the account, its role and the command list |
| `/status` | State of the managed panel |
| `/panels` | Every panel with its state |
| `/backup` | Create a backup and send it |
| `/restore` | List backups; `/restore NAME` restores one that is named |
| `/ssl` | Certificate state of the managed panel |
| `/renew` | Renew the certificates of the managed panel |
| `/users` | Account count and active accounts |
| `/traffic` | Traffic summary |
| `/alerts` | The alerts that currently hold |
| `/update` | Check for a BaToHub update |
| `/restart` | Restart the managed panel |
| `/logs` | Last lines of the panel log |

A command that carries an argument is checked against the permission that operation needs, exactly as the interface does. A listed user whose account does not hold the permission receives a refusal that names the permission.

### 22.3 Authentication

- A Telegram user id that is not listed is refused, and nothing is sent back to that chat. The refusal is recorded in the log; a reply would tell anyone who reaches the bot that this endpoint belongs to a BaToHub instance.
- A listed user whose chat is not permitted is refused in the same way.
- A listed user that maps to an account that does not exist is refused and the missing account is recorded.

### 22.4 Logging

`${LOG_DIR}/telegram-bot.log` records every command with the Telegram user id, the chat id, the BaToHub account and the command name, and every refusal with its reason. The token is never written to any log, and a command that fails records the failure without the message body.

### 22.5 Service

| Command | Description |
| --- | --- |
| `BaToHub --bot status` | Configuration state, listed users, allowed chats and log path |
| `BaToHub --bot service` | Install and enable the systemd unit that runs the bot |
| `BaToHub --bot remove-service` | Disable and remove that unit |
| `BaToHub --bot logs` | Log tail of the bot |
| `BaToHub --bot once` | Process one polling round; used by the verification suite |
| `BaToHub --bot users` | The listed users and the account each maps to |
| `BaToHub --bot check USER_ID [CHAT_ID]` | Report whether that user is authorised |

### 22.6 What the Bot Never Sends

The bot never sends a configuration file, a credential, a private key or a token. A backup it sends is encrypted when a password is configured, and is otherwise marked in its caption as unencrypted. Logs it sends are the last lines of the panel log, which the operator already controls through the panel.

## 23. Configuration Reference

### 23.1 batohub.conf

`/etc/batohub/batohub.conf`, mode 0600, created by the installer, never overwritten by an update:

| Key | Default | Description |
| --- | --- | --- |
| `APP_NAME` | `BaToHub` | Project name shown in the interface |
| `APP_VERSION` | `0.0.5` | Version, kept in step with the `VERSION` file |
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
| `REPORT_KEEP` | `20` | Number of report exports kept in the export directory |
| `API_TIMEOUT` | `30` | Seconds before a panel API request is abandoned |
| `TELEGRAM_MAX_UPLOAD_BYTES` | `45000000` | Size above which a delivered archive is split into parts |

### 23.2 panel.conf

`/etc/batohub/panel.conf`, mode 0600, written by BaToHub:

| Key | Description |
| --- | --- |
| `PANEL` | Panel identifier, for example `rebecca` |
| `PANEL_PORT` | Port recorded for the panel at selection time |
| `PANEL_PATH` | Installation path recorded at selection time |
| `PANEL_DOMAIN` | Domain read from the panel configuration when one is present |
| `INSTALLED_AT` | Date and time the panel was selected |

### 23.3 Additional Configuration Files

| File | Mode | Content |
| --- | --- | --- |
| `${CONFIG_DIR}/nodes.conf` | 0600 | Panel endpoints and node API credentials (section 13.2) |
| `${CONFIG_DIR}/telegram.conf` | 0600 | Backup delivery token, chat, schedule and retention (section 15.1) |
| `${CONFIG_DIR}/telegram_bot.conf` | 0600 | Management bot token, listed users and allowed chats (section 22.1) |
| `${CONFIG_DIR}/alerts.conf` | 0600 | Alert enable state, thresholds, cooldowns and delivery credentials (section 19) |
| `${CONFIG_DIR}/admins.conf` | 0600 | Accounts with their roles and password hashes (section 20.1) |
| `${CONFIG_DIR}/ssl/<panel>.conf` | 0600 | Registered names per panel with purpose and method (section 14.2) |
| `${CONFIG_DIR}/ssl/dns.conf` | 0600 | DNS provider credentials for wildcard certificates (section 14.3) |

Every file that holds a credential is created at mode 0600 with owner root:root and is re-checked before it is read.

### 23.4 State Layout

| Path | Content |
| --- | --- |
| `${STATE_DIR}/nodes/` | One node record per node, mode 0600 (section 13.1) |
| `${STATE_DIR}/panels/<panel>/ssl/<target>/` | Certificate and key for one registered name |
| `${STATE_DIR}/panels/<panel>/templates/` | Templates staged for a panel that serves them from its own database |
| `${STATE_DIR}/templates-backup/` | Previous template copies, so a removal or replacement is reversible |
| `${STATE_DIR}/backups/` | Backup archives and the delivery ledger |
| `${STATE_DIR}/reports/` | Report exports: a mode 0750 directory with mode 0600 files |
| `${STATE_DIR}/alerts/` | One cooldown file per alert |
| `${STATE_DIR}/telegram-bot.offset` | Last processed Telegram update, so a restart does not repeat a command |
| `${STATE_DIR}/tools/<tool>/` | Records BaToHub keeps for a tool, such as the detected install path |

The update never writes outside `${INSTALL_DIR}`, `${CONFIG_DIR}`, `${STATE_DIR}` and `${LOG_DIR}`, and never touches a path named in `USER_MANAGED_PATHS`.

### 23.5 Environment Variables

`INSTALL_DIR`, `CONFIG_DIR`, `STATE_DIR`, `LOG_DIR`, `BACKUP_DIR`, `BACKUP_KEEP`, `GLOBAL_CMD_NAME`, `GITHUB_REPO`, `GITHUB_BRANCH`, `INTEGRITY_HARD_FAIL`, `REPORT_KEEP`, `API_TIMEOUT`, `TELEGRAM_MAX_UPLOAD_BYTES`, `BATOHUB_ADMIN` and the `NODES_*` keys override the configuration files when set. The installer additionally reads `BATOHUB_RELEASE_TAG`, `BATOHUB_SOURCE_DIR` and `BATOHUB_ALLOW_UNVERIFIED_FALLBACK` (section 3.3). `SSL_ACME_BIN`, `FOXIMA_REPO_URL`, `FOXIMA_INSTALLER_URL`, `FOXIMA_PROJECT_DIR`, `FOXIMA_MANAGEMENT_CMD` and the per-panel `*_SCRIPT_URL` / `*_INSTALLER_URL` variables override the upstream sources and paths, which is useful for mirrors and relocated installations.

## 24. Command Reference

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
| `BaToHub --nodes CMD` | Node management: `list`, `panels`, `panel-list`, `show`, `restart`, `logs`, `bundle`, `add`, `remove` (section 13.4) |
| `BaToHub --ssl CMD` | Certificate names: `list`, `register`, `unregister`, `issue`, `renew`, `status`, `revoke` (section 14.4) |
| `BaToHub --backup-deliver CMD` | Telegram delivery: `status`, `test`, `send`, `ledger` (section 15.4) |
| `BaToHub --migration CMD` | Migration: `pairs`, `preview`, `run` (section 16.4) |
| `BaToHub --server CMD` | Server tools: `firewall`, `fail2ban`, `bbr`, `limits`, `time` (section 17.6) |
| `BaToHub --container CMD` | Containers: `list`, `mode`, `status`, `logs`, `restart`, `stats`, `update` (section 18.4) |
| `BaToHub --alerts CMD` | Alerts: `status`, `types`, `check`, `run`, `enable`, `disable`, `threshold`, `schedule`, `unschedule` (section 19.6) |
| `BaToHub admin CMD` | Accounts: `list`, `status`, `permissions`, `roles`, `add`, `remove`, `passwd`, `role`, `check` (section 20.5) |
| `BaToHub --reports CMD` | Reports: `list`, `show`, `export`, `exports`, `rotate` (section 21.4) |
| `BaToHub --bot CMD` | Telegram bot: `status`, `service`, `remove-service`, `logs`, `once`, `users`, `check` (section 22.5) |
| `BaToHub --alerts-run` | The scheduled entry point for the alert timer |

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

## 25. FAQ

**Does BaToHub remove or reset my panel when I switch panels?**
No. Switching rewrites one key in `panel.conf`. The previous panel keeps running untouched.

**Does the uninstaller delete panel data?**
No. The uninstaller removes `/opt/batohub`, `/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub` and the global command link. Panels, their databases, their configuration and their certificates outside BaToHub state storage are never removed. Backup archives can be moved to `/var/backups/batohub-<timestamp>` instead of being deleted.

**Why does the installer refuse to continue with a checksum error?**
The downloaded release asset did not match its published SHA-256. Nothing was extracted and nothing was changed. Check network integrity and re-run.

**Can I install a specific version of BaToHub?**
Yes. Set `BATOHUB_RELEASE_TAG=v0.0.5` before running the installer (section 3.3).

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

**Does BaToHub need access to the panel API?**
Only for the operations that use it: node registration and deregistration, migration, the reports that read accounts, and the alert that compares a panel version with the published one. The endpoint and the credential are declared in `/etc/batohub/nodes.conf`, and a panel that is not configured for API access has those operations unavailable.

**Does BaToHub install an agent on a remote node?**
No. It registers the node through the panel API and prints the installer command of the panel itself. The remote machine is prepared with the panel's own installer, and BaToHub writes nothing there.

**Are alerts delivered by default?**
No. No alert is enabled when the configuration file is created, and an alert with no entry in the file is off. Enable the alerts you want, set their thresholds, then schedule the timer.

**Can a Telegram user other than the listed ones use the bot?**
No. A user id that is not listed is refused, the refusal is recorded, and nothing is sent back to that chat. A listed user runs with the permissions of the BaToHub account that user id is mapped to, and the same permission gate that the menu uses applies.

**Which version does a panel installation use?**
The newest stable release is the default, and the other releases the panel's own repository publishes are offered before the installation runs. The panel's official installer performs the installation with the version argument of the release that was chosen.
