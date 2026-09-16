# BaToHub

A modular TUI server management hub, written in Bash, that manages VPN and proxy panels and tools from one interface.

![Bash](https://img.shields.io/badge/shell-Bash-4EAA25)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)
![Platform](https://img.shields.io/badge/platform-Linux-fcc624)
![Architecture](https://img.shields.io/badge/design-Panel--first-lightgrey)

## Quick Access

- [About BaToHub](#about-batohub)
- [Features](#features)
- [Supported Panels](#supported-panels)
- [Supported Tools](#supported-tools)
- [Requirements](#requirements)
- [Installation](#installation)
- [Documentation](#documentation)
- [Donation](#donation)
- [License](#license)
- [Contact](#contact)

## About BaToHub

BaToHub is a server management hub that runs as a single command on a Linux server. It discovers panels and tools from its own module directory, manages one panel at a time, and exposes SSL, subscription template, backup, update and integrity operations for that panel through a text interface and a command line interface. It installs into a central directory and removes cleanly without touching panel data.

## Features

Architecture:

- Panel-first design. Every panel is a self-contained module with its own metadata, SSL, template, update and menu code.
- Single entry point. The `BaToHub` command works from any directory and opens the same central interface.
- Filesystem discovery. Adding a panel or tool directory is enough for the loader to see it.

Panel management:

- Detection of installed panels through paths, systemd units and listening ports.
- Install and update through each panel's official installer or updater.
- Version detection and selection. Each panel lists the releases published by its own repository and installs the release you choose through that panel's official installer. The newest stable release is the default, a development channel is offered where the installer declares one, and a panel whose installer always installs the newest release is reported as not supporting version pinning.
- The installed version is read back after the operation and the version change is recorded with a timestamp under `/var/log/batohub/`.
- Per-panel menus with state indicators, and a non-interactive command interface for automation.

SSL:

- Certificate issuance and renewal per panel through acme.sh, stored per panel under BaToHub state storage.
- Registration of certificate paths with a panel only when that panel's configuration already declares the option.
- Bare-IP certificate support where the panel allows it (VPN-UI).

Subscription templates:

- One shared subscription template with an optional per-panel override.
- Templates are staged or applied per panel, and the previous file is always backed up first.

Backup and restore:

- Full backups of configuration, state and log directories plus the declared panel paths.
- Checksummed archives, transactional restore with a safety backup, and import of external archives.
- Restore validates every archive member against a strict allowlist before anything is written.

Self-update:

- Downloads a pinned release, verifies its SHA-256 against the published checksum and manifest, and refuses an unverified download.
- Never overwrites operator configuration, panel state, logs, or declared user-managed paths.
- Rolls back to the previous installation when post-update verification fails.

Security:

- Integrity manifest with a SHA-256 entry for every shipped file, verified on demand and after every update.
- Strict file and directory permissions; private keys are never printed.
- No telemetry, and no outbound call other than the downloads and the version listings the operator requests.

## Supported Panels

| Name | Description | Install Path | Service Name | Default Port | Notes |
| --- | --- | --- | --- | --- | --- |
| Rebecca | Go binary or Docker Compose panel | `/opt/rebecca` | `rebecca` | 8000 | Configuration in `/opt/rebecca/.env` |
| Marzban | Python and React panel | `/opt/marzban` | `marzban` | 8000 | Template paths read from `.env` |
| PasarGuard | Python panel | `/opt/pasarguard` | `pasarguard` | 8000 | Template paths read from `.env` |
| 3X-UI | Sanaei web panel | `/usr/local/x-ui` | `x-ui` | 2053 | Database in `/etc/x-ui` |
| VPN-UI | Fork of 3X-UI, managed independently | `/opt/vpn-ui` | `vpn-ui` | 2053 | Supports bare-IP certificates |

## Supported Tools

| Name | Description | Requirements | Notes |
| --- | --- | --- | --- |
| Foxima | PHP management interface for panel families | Docker, curl, wget, unzip | Drives the official installer, which deploys a Docker Compose stack and owns its configuration; BaToHub never writes the Foxima configuration and never removes the stack, its volumes or its data |

## Requirements

| Component | Requirement |
| --- | --- |
| Operating system | Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, or Debian 12 |
| Architecture | amd64 or arm64 |
| Privileges | Root, for installation and for operations that manage system services |
| Shell | Bash 4.4 or newer |
| Commands | curl, tar, gzip, python3, openssl; rsync and util-linux are installed by the installer on Ubuntu and Debian |
| Init system | systemd where present; its absence is detected and reported |
| Certificates | acme.sh, only when a certificate is issued through BaToHub |

## Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

The one-liner runs the installer from the main branch, and the installer itself downloads the newest published release, verifies its SHA-256, and installs from that pinned source. Re-running the installer on an installed server preserves the existing configuration.

Manual install, configuration, troubleshooting, and the full command reference are in [DOCS.md](DOCS.md).

## Documentation

- Full documentation: [DOCS.md](DOCS.md)
- Security model: [SECURITY.md](SECURITY.md)
- Persian documentation: [README.fa.md](README.fa.md) and [DOCS.fa.md](DOCS.fa.md)

## Donation

If BaToHub is useful to you, donations are accepted through the contact handle below.

## License

BaToHub is released under the GNU General Public License, version 3. The full text is in [LICENSE](LICENSE).

Any use, modification, fork, sublicensing or redistribution of BaToHub must comply with GPL-3.0 in full. Every fork and every redistribution must preserve the original copyright notice, the project name BaToHub, and the original repository URL, https://github.com/isAsli/BaTo-Hub.

Custom or proprietary variants are not permitted under this license. If you need a custom or private version, use the contact handle below.

BaToHub is free and open source. There are no paid tiers, no license enforcement, no telemetry, and no outbound call to a licensing server.

## Contact

Support, bug reports, and ideas: **@DatPHP**
