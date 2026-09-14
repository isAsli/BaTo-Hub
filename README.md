# BaToHub

BaToHub is a Bash-based TUI for managing multiple VPN and proxy panels from one server.

## What BaToHub is and what it is not

BaToHub is a single interface for managing multiple panels from one server.

BaToHub is not:
- a panel installer
- a panel itself
- a paid service
- a license enforcement system
- telemetry software
- a remote code execution platform

BaToHub only manages its own changes. It does not remove panels or delete panel data.

## Supported panels

Supported panels in this release:
- Rebecca
- PasarGuard
- 3X-UI (Sanaei)

Marzban is not supported.

## Features

Core:
- Panel-first first-run selection
- Panel persistence in `/etc/batohub/panel.conf`
- Panel-specific main menu
- Server information
- BaToHub self-update from GitHub
- Integrity checks for managed files
- Backup, restore, and import
- Uninstall that keeps panels intact
- Secure state storage permissions

Panel management:
- Panel detection and version reporting
- Panel status
- Panel-specific SSL management
- Panel-specific subscription templates
- Panel logs
- Panel update and status

Security and quality:
- `set -euo pipefail` across shell sources
- Quoted variable expansions
- Temporary files from `mktemp`
- Locked shared state where practical
- No contact handle in source code
- No telemetry or network calls in the core

## Architecture

```
/opt/BaToHub/
  bin/
    batohub
    uninstall
  core/
    main.sh
    module_loader.sh
    panel_manager.sh
    ssl_manager.sh
    template_manager.sh
    backup_manager.sh
    update.sh
  lib/
    common.sh
  security/
    integrity.sh
  panels/
    <panel>/
      panel.json
      module.sh
      ssl/module.sh
      templates/module.sh
      templates/subscription/index.html
      update/module.sh
      menu/module.sh
  templates/
  VERSION
  manifest.json
```

System paths:
```
/etc/batohub/
  panel.conf
  batohub.conf
  integrity.sha256
/var/lib/batohub/
/var/log/batohub/
/usr/local/bin/BaToHub -> /opt/BaToHub/bin/batohub
```

Data flow:
1. `BaToHub` runs `bin/batohub`
2. `bin/batohub` runs `core/main.sh`
3. `main.sh` loads panel discovery from `panels/`
4. If no panel is configured, first-run panel selection is shown
5. Panel selection is persisted to `panel.conf`
6. The panel-specific menu is loaded
7. Operations are routed through panel modules

## Requirements

Operating systems:
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

Architectures:
- amd64
- arm64

Dependencies:
- bash
- curl
- ca-certificates
- openssl
- unzip
- rsync
- python3
- jq
- certbot for Rebecca SSL

Root access is required for installation and most management actions.

## Quick install

Run one command as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

What that does:
- checks for root privileges
- installs required system packages
- creates the main directories under `/opt/BaToHub`
- sets permissions
- installs the global command
- writes the integrity manifest

After install, run:

```bash
BaToHub
```

## Manual install

1. Download the source to a temporary location on the server.
2. Run `install.sh` as root.
3. Verify the global command exists.
4. Run `BaToHub` and select a panel if needed.

Example:

```bash
apt-get update
apt-get install -y curl ca-certificates openssl unzip rsync python3 jq certbot
bash ./install.sh
BaToHub
```

## Post-install verification

After installation, verify:
- `BaToHub` starts
- the version matches `VERSION`
- `/etc/batohub/panel.conf` is not world-readable
- `/etc/batohub/batohub.conf` is not world-readable
- `/etc/batohub/integrity.sha256` exists
- `/var/lib/batohub` and `/var/log/batohub` have correct permissions

## Quick start

1. Run `BaToHub`.
2. Select a panel if prompted.
3. Use the panel menu for SSL, templates, update, logs, backup, restore, or import.

## Command reference

| Command | Purpose |
| --- | --- |
| `BaToHub` | Open the central menu |
| `install.sh` | Install BaToHub as root |
| `bin/uninstall` | Remove BaToHub-managed files with confirmation |
| `sha256sum -c /etc/batohub/integrity.sha256` | Verify managed file integrity |

Menu actions are interactive. Destructive actions require an explicit confirmation phrase.

## Panel system

Every panel is a directory under `panels/<name>` with at least:
- `panel.json`
- `module.sh`

`panel.json` describes the panel:

```json
{
  "name": "example",
  "display_name": "Example",
  "version": "0.0.2",
  "description": "Example panel",
  "service_name": "example",
  "default_port": "80",
  "default_path": "/opt/example",
  "config_paths": ["/opt/example/.env"],
  "requirements": ["curl", "ca-certificates", "openssl"],
  "ssl_method": "manual",
  "template_method": "disabled"
}
```

`module.sh` exposes the panel interface:
- `panel_detect`
- `panel_version`
- `panel_status`
- `panel_install`
- `panel_uninstall`
- `panel_ssl_issue`
- `panel_ssl_renew`
- `panel_template_apply`
- `panel_template_remove`
- `panel_logs`
- `panel_update`
- `panel_menu`

Example of writing a new panel:

1. Create `panels/<name>/panel.json`.
2. Create `panels/<name>/module.sh`.
3. Implement the required functions.
4. Add `ssl/module.sh` and `templates/module.sh` if the panel supports them.
5. Run `install.sh` after adding the panel.

## Configuration reference

### batohub.conf

| Key | Description | Default |
| --- | --- | --- |
| `APP_NAME` | Application name | `BaToHub` |
| `APP_VERSION` | Application version | `0.0.2` |
| `GITHUB_REPO` | GitHub repository | `isAsli/BaTo-Hub` |
| `GITHUB_BRANCH` | Branch used for update | `main` |
| `UPDATE_MANIFEST` | Manifest URL used for update checks | configured centrally |
| `INSTALL_DIR` | Main application directory | `/opt/batohub` |
| `CONFIG_DIR` | Configuration directory | `/etc/batohub` |
| `STATE_DIR` | Persistent state directory | `/var/lib/batohub` |
| `LOG_DIR` | Log directory | `/var/log/batohub` |
| `STATE_DIR_MODE` | Mode for state directories | `750` |
| `BACKUP_DIR` | Backup directory | `/var/lib/batohub/backups` |
| `BACKUP_KEEP` | Number of backups to keep | `5` |
| `GLOBAL_CMD_NAME` | Global command path | `/usr/local/bin/BaToHub` |

### panel.conf

| Key | Description | Example |
| --- | --- | --- |
| `PANEL` | Selected panel name | `rebecca` |
| `PANEL_PORT` | Panel port | `8080` |
| `PANEL_PATH` | Panel path | `/opt/rebecca` |
| `PANEL_DOMAIN` | Panel domain if known | `example.test` |
| `INSTALLED_AT` | Installation timestamp | `2026-09-14 10:00:00` |

## Backup, restore, and import

Backup includes:
- `/etc/batohub`
- `/var/lib/batohub`
- `/var/log/batohub`
- panel-specific config paths
- SSL certificates and keys used by the panel
- templates applied by BaToHub
- metadata with version, panel name, panel version, timestamp, and managed files

Backup format:
- gzip-compressed tarball
- stored in `/var/lib/batohub/backups/<timestamp>.tar.gz`
- checksum file alongside
- permissions 600, owner root:root
- rotation keeps the configured number of backups

Restore:
- list backups with date and size
- verify checksum before restoring
- extract to a temp directory
- move files into place transactionally
- create a safety backup before restoring
- do not overwrite files outside declared paths

Import:
- import a backup file from an external path
- verify checksum if available
- use the same transactional restore flow

## Self-update

Source of truth is the GitHub repository `isAsli/BaTo-Hub`, branch `main`.

Update behavior:
- use git when available, otherwise fall back to HTTPS checks
- take a full backup before updating
- compare local files against remote
- add new remote files
- remove remote-removed files only if they are not user-managed
- replace modified files
- leave unchanged files untouched

Files that must never be touched by update:
- `/etc/batohub/panel.conf`
- `/etc/batohub/batohub.conf`
- `/var/lib/batohub`
- `/var/log/batohub`
- any path declared as user-managed in panel configuration

After update:
- run `bash -n` on shell files
- verify panel discovery still works
- print a diff summary
- roll back automatically if verification fails

## Security model

BaToHub uses:
- centralized configuration with restrictive permissions
- integrity manifest for managed files
- locked writes for shared state where practical
- `mktemp` for temporary files
- quoted expansions and strict shell mode
- restricted permissions on private keys and sensitive config
- plain-text logging without terminal escapes

Limitations:
- root access can modify or delete local files
- SSL for Rebecca depends on Certbot and port 80 availability
- update trust depends on the repository branch and presence of git
- third-party panels are outside BaToHub control unless the integration code itself is affected

## Logging and troubleshooting

Logs are written to:
`/var/log/batohub/batohub.log`

Common checks:
- verify permissions on `/etc/batohub`, `/var/lib/batohub`, and `/var/log/batohub`
- verify `panel.conf` and `batohub.conf`
- run the integrity check
- review logs for recent errors
- check whether required commands exist
- for Rebecca SSL, check port 80 availability

## Uninstall

Run the uninstall command from the menu or directly:

```bash
/opt/BaToHub/bin/uninstall
```

The uninstaller:
- shows what will be removed
- asks for confirmation
- removes BaToHub-owned files
- keeps panels and panel data intact

## License

BaToHub is free and open source software released under the GNU General Public License version 3.

See `LICENSE` for the full license text.

https://www.gnu.org/licenses/gpl-3.0.html

## Modification and redistribution policy

Any use, modification, fork, or redistribution must comply with GPL-3.0 in full and must preserve the original copyright notice, the project name BaToHub, and the original repository URL.

Custom or proprietary versions are not permitted under this license. Anyone needing a custom version must contact @DatPHP.

## Support and contact

For support, bug reports, and ideas, contact @DatPHP.

## Credits

Copyright (C) BaToHub
