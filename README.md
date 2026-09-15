# BaToHub

BaToHub is a modular command line management hub for proxy and VPN panels, written in Bash and driven from a single interactive interface.

Persian documentation: [README.fa.md](README.fa.md)

## 1. Project name and one line description

BaToHub is a central server manager written in Bash that detects, configures and maintains supported proxy and VPN panels from one menu.

## 2. What BaToHub is and what it is not

What it is:

- A panel-first management hub with one entry point: the `BaToHub` command.
- A set of independent panel modules that share one loader, one configuration and one backup format.
- A tool that keeps its own files under one installation directory and never rewrites a panel it does not manage.
- A maintenance interface for SSL certificates, subscription templates, backups, updates, logs and integrity checks.

What it is not:

- It is not a replacement for a panel. Each panel keeps its own installer, service, database and interface.
- It is not a hosting control panel and it does not manage unrelated services on the server.
- It is not a subscription generator. Where a panel generates subscription output from its own settings, BaToHub says so and does not modify that panel's database.
- It does not claim to make an installation immutable. A user with root access can change any local file; BaToHub records an integrity manifest and reports differences.

## 3. Supported panels

| Panel | Service | Install path | Default port | SSL |
| --- | --- | --- | --- | --- |
| Rebecca | `rebecca` | `/opt/rebecca` | 8000 | acme.sh issuance into BaToHub state storage |
| Marzban | `marzban` | `/opt/marzban` | 8000 | acme.sh issuance, uvicorn options updated when present |
| PasarGuard | `pasarguard` | `/opt/pasarguard` | 8000 | acme.sh issuance, panel options updated when present |
| 3X-UI (Sanaei) | `x-ui` | `/usr/local/x-ui` | 2053 | acme.sh issuance, panel CLI used only when it advertises support |
| VPN-UI | `vpn-ui` | `/opt/vpn-ui` | 2053 | acme.sh issuance, domain or bare IPv4 address |

Rebecca and Marzban are separate installations even though Rebecca descends from Marzban. 3X-UI and VPN-UI are also managed independently, with their own paths, services and state.

## 4. Supported tools

| Tool | Purpose | Notes |
| --- | --- | --- |
| Foxima | PHP management interface for several panel families | BaToHub checks the prerequisites and runs the official installer where the operator asks for it |

## 5. Features

Panel management

- Automatic detection of installed panels through paths, systemd units and listening ports.
- First-run panel selection that always asks the operator to confirm a detected panel.
- Panel-specific menus for SSL, templates, status, update, logs and change removal.
- Panel installation delegated to each panel's official installer, downloaded over HTTPS.

SSL

- One certificate directory per panel under `/var/lib/batohub/panels/<panel>/ssl/`.
- acme.sh issuance and renewal, with the reload command recorded per certificate.
- DNS comparison before issuance, with explicit messages for missing records and mismatched addresses.
- Port 80 checks that name the current listener instead of failing silently.
- A marker file per certificate directory, so BaToHub refuses to touch another panel's certificate storage.

Templates

- A bundled subscription template for panels that document a custom template directory.
- Template staging for panels that generate subscriptions internally, clearly labelled as staging.
- Every replaced template is copied into `/var/lib/batohub/templates-backup/` first.

Backup and recovery

- One command creates a gzip archive with a SHA-256 sidecar and a metadata file.
- Restore verifies the checksum and refuses any archive member that is not declared in the metadata.
- A safety backup is created before every restore.
- Backup rotation keeps the newest five archives by default.

Update

- BaToHub updates itself from its own GitHub repository over HTTPS.
- Protected paths (`/etc/batohub`, `/var/lib/batohub`, `/var/log/batohub`, operator declared paths) are never replaced or deleted.
- The new tree is checked with `bash -n`, the panel interfaces are validated, and the integrity manifest is rebuilt and verified.
- A failed verification restores the previous tree from a snapshot taken before the update.

Operations

- Status summary for the server, the panel, the certificate and the integrity manifest.
- Log records for every action, with timestamps, appended to `/var/log/batohub/batohub.log`.
- Uninstall that removes only BaToHub-owned files and leaves panels, their data and their databases untouched.

## 6. Architecture

```
                    +-------------------------------+
                    |  /usr/local/bin/BaToHub       |
                    |  link to bin/batohub          |
                    +---------------+---------------+
                                    |
        +---------------------------+---------------------------+
        |                        core/main.sh                   |
        |  CLI flags, menus, panel detection, dispatch          |
        +---+------------------+------------------+-------------+
            |                  |                  |
   +--------v-------+  +-------v--------+  +------v--------+
   | core/panel_    |  | core/backup_   |  | core/update.sh|
   | loader.sh      |  | manager.sh     |  | self update   |
   +--------+-------+  +-------+--------+  +------+--------+
            |                  |                  |
   +--------v------------------v------------------v--------+
   |  lib/common.sh  lib/panel_helpers.sh                   |
   |  lib/ssl_helpers.sh  lib/template_helpers.sh            |
   |  lib/backup_helpers.sh                                 |
   +---------------------------+----------------------------+
                               |
              +----------------+----------------+
              |                                 |
     panels/<name>/module.sh               tools/<name>/module.sh
     panels/<name>/{ssl,templates,          tools/foxima/{install,menu}
       update,menu}/module.sh

State:     /etc/batohub        configuration and integrity manifest
           /var/lib/batohub    panel state, certificates, backups
           /var/log/batohub    logs
```

## 7. Requirements

- Ubuntu 22.04 LTS, Ubuntu 24.04 LTS or Debian 12.
- amd64 or arm64.
- Root access for installation and for operations that manage system services.
- Bash 4.4 or newer, `curl`, `tar`, `gzip`, `python3`, `openssl`.
- `rsync` and `util-linux` (for `flock`) are recommended; the installer adds them on Ubuntu and Debian.
- `systemd` is used when it is present. BaToHub detects its absence and reports that a service could not be restarted instead of pretending otherwise.
- `acme.sh` is required only when a certificate is issued through BaToHub.
- The target panel must already be installed, or installed through BaToHub's install action.

## 8. Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

The installer runs as root, installs missing packages on Ubuntu and Debian, copies the release into `/opt/batohub`, creates `/etc/batohub` when it does not exist, installs the global command, validates every panel and tool interface, and writes the integrity manifest. Running it again on an installed server preserves the existing configuration.

## 9. Manual install

```bash
git clone https://github.com/isAsli/BaTo-Hub.git
cd BaTo-Hub
sudo bash install.sh
```

Then confirm the installation:

```bash
BaToHub --version
BaToHub --validate
```

The installer can be pointed at another location when the defaults do not fit:

```bash
sudo BATOHUB_SOURCE_DIR="$PWD" INSTALL_DIR=/opt/batohub GLOBAL_CMD_NAME=/usr/local/bin/BaToHub bash install.sh
```

## 10. Post-install verification

| Command | What it confirms |
| --- | --- |
| `BaToHub --version` | The installed version, read from `/opt/batohub/VERSION` |
| `BaToHub --validate` | Every shipped panel and tool loads and exports the required functions |
| `BaToHub --check` | The files on disk match the integrity manifest |
| `BaToHub --status` | Panel state, panel version, service name and certificate directory |
| `BaToHub --detect` | Panels found on this server |

## 11. Quick start

```bash
BaToHub
```

On the first run BaToHub looks for supported panels. When it finds one it asks you to confirm it, then stores the choice in `/etc/batohub/panel.conf` with mode 0600 and opens the panel menu.

If nothing is found, BaToHub reports that no compatible panel is installed and offers to install one, or opens a reduced menu with panel installation, tools, settings, self-update and the integrity check.

## 12. Command reference

| Command | Description |
| --- | --- |
| `BaToHub` | Open the interactive interface |
| `BaToHub --menu` | Same as running with no arguments |
| `BaToHub --help` | Print the usage text |
| `BaToHub --version` | Print the version |
| `BaToHub --list-panels` | List the supported panels |
| `BaToHub --detect` | List the panels detected on this server |
| `BaToHub --status` | Print the status summary |
| `BaToHub --select-panel NAME` | Store the panel BaToHub manages |
| `BaToHub --panel NAME CMD` | Run one panel command without the menu |
| `BaToHub --tools` | List the supported tools |
| `BaToHub --backup` | Create a backup now |
| `BaToHub --restore FILE` | Restore a backup archive |
| `BaToHub --update` | Update BaToHub from GitHub |
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
| `template-remove` | Remove the BaToHub-managed template |
| `update` | Run the panel's official updater |
| `logs` | Print the panel log tail |

Example:

```bash
BaToHub --panel rebecca status
BaToHub --panel 3x-ui version
```

## 13. Panel system

A panel is a directory under `panels/` containing `panel.json` and `module.sh`, plus `ssl/`, `templates/`, `update/` and `menu/` sub-modules. BaToHub discovers panels from the filesystem, so adding a directory is enough for the loader to see a new panel.

`panel.json` fields:

| Field | Meaning |
| --- | --- |
| `name` | Directory name and panel identifier, lowercase with hyphens |
| `display_name` | Name shown in menus |
| `version` | Panel integration version, kept in step with the release |
| `description` | One factual sentence |
| `service_name` | systemd unit name |
| `default_port` | Port used for detection and reporting |
| `default_path` | Installation directory |
| `config_paths` | Configuration files BaToHub may read and back up |
| `data_paths` | Data locations BaToHub may back up |
| `database_type` | Database engines the panel supports |
| `cli_name` | Command line tool used for version and detection |
| `requirements` | Packages the integration expects |
| `ssl_method` | How certificates are handled for this panel |
| `template_method` | How subscription templates are handled for this panel |
| `supports_bare_ip_ssl` | Whether a certificate for a bare address is supported |
| `supports_reseller` | Whether the panel has reseller accounts |
| `update_method` | Official updater used by the update action |

Required module functions:

`panel_detect`, `panel_version`, `panel_status`, `panel_install`, `panel_uninstall`, `panel_ssl_issue`, `panel_ssl_renew`, `panel_ssl_status`, `panel_ssl_remove`, `panel_template_apply`, `panel_template_remove`, `panel_template_status`, `panel_update`, `panel_logs`, `panel_menu`.

The loader exports the context a module uses: `PANEL_NAME`, `PANEL_DISPLAY`, `PANEL_JSON`, `PANEL_MODULE_DIR`, `PANEL_PATH`, `PANEL_SERVICE`, `PANEL_PORT`, `PANEL_CLI`, `PANEL_SSL_DIR`, `PANEL_TEMPLATE_DIR`.

Writing a new panel:

```bash
mkdir -p panels/my-panel/{ssl,templates,update,menu}
```

```json
{
  "name": "my-panel",
  "display_name": "My Panel",
  "version": "0.0.3",
  "description": "My Panel integration.",
  "service_name": "my-panel",
  "default_port": 8000,
  "default_path": "/opt/my-panel",
  "config_paths": ["/opt/my-panel/.env"],
  "data_paths": ["/var/lib/my-panel"],
  "database_type": "sqlite|postgres",
  "cli_name": "my-panel",
  "requirements": ["curl", "openssl"],
  "ssl_method": "acme.sh issuance into BaToHub state storage",
  "template_method": "panel settings; BaToHub stages template files",
  "supports_bare_ip_ssl": false,
  "supports_reseller": false,
  "update_method": "official installer"
}
```

```bash
cat >panels/my-panel/module.sh <<'MODULE'
#!/usr/bin/env bash
set -Eeuo pipefail

panel_detect() {
  [[ -d "$PANEL_PATH" ]] && return 0
  service_registered "$PANEL_SERVICE" && return 0
  return 1
}

panel_version() { "$PANEL_CLI" --version 2>/dev/null | head -n 1 || printf 'unknown\n'; }
panel_status() { panel_status_generic; }
panel_install() { panel_fetch_official_installer "https://example.invalid/install.sh" ""; }
panel_uninstall() {
  printf 'BaToHub does not remove %s.\n' "$PANEL_DISPLAY"
}
panel_logs() { panel_logs_generic "$PANEL_SERVICE" "$PANEL_PATH"; }
panel_update() { panel_submodule update && panel_update_impl; }
panel_ssl_issue() { panel_submodule ssl && ssl_issue; }
panel_ssl_renew() { panel_submodule ssl && ssl_renew; }
panel_ssl_status() { panel_submodule ssl && ssl_status; }
panel_ssl_remove() { panel_submodule ssl && ssl_remove; }
panel_template_apply() { panel_submodule templates && template_apply; }
panel_template_remove() { panel_submodule templates && template_remove; }
panel_template_status() { panel_submodule templates && template_status; }
panel_menu() { panel_submodule menu && panel_menu_impl; }
MODULE
```

Then implement the sub-modules and run:

```bash
BaToHub --validate
BaToHub --panel my-panel status
```

## 14. Tool system

A tool is a directory under `tools/` with `tool.json` and `module.sh`, plus optional `install/` and `menu/` sub-modules. Tools are independent of the selected panel and appear in the Tools menu.

Required tool functions: `tool_detect`, `tool_version`, `tool_status`, `tool_install`, `tool_uninstall`, `tool_menu`.

Foxima is the shipped example. It is a PHP interface that is normally deployed on a hosting stack, so the integration:

- checks for a PHP runtime and a database client before anything is downloaded;
- asks for the install directory and refuses to install into system directories;
- runs the official installer from inside that directory;
- records the installation path in `/var/lib/batohub/tools/foxima/install.path`;
- removes only an installation BaToHub recorded, and keeps a compressed copy of it first.

## 15. Configuration reference

`/etc/batohub/batohub.conf` (mode 0600, created by the installer, never overwritten by an update):

| Key | Default | Description |
| --- | --- | --- |
| `APP_NAME` | `BaToHub` | Project name shown in the interface |
| `APP_VERSION` | `0.0.3` | Version, kept in step with the `VERSION` file |
| `INSTALL_DIR` | `/opt/batohub` | Program files |
| `CONFIG_DIR` | `/etc/batohub` | Configuration and integrity manifest |
| `STATE_DIR` | `/var/lib/batohub` | Panel state, certificates, backups, locks |
| `LOG_DIR` | `/var/log/batohub` | Log files |
| `BACKUP_DIR` | `/var/lib/batohub/backups` | Backup archives |
| `BACKUP_KEEP` | `5` | Number of archives to keep |
| `GITHUB_REPO` | `isAsli/BaTo-Hub` | Repository used by self-update |
| `GITHUB_BRANCH` | `main` | Branch used by self-update |
| `GLOBAL_CMD_NAME` | `/usr/local/bin/BaToHub` | Path of the global command |
| `USER_MANAGED_PATHS` | empty | Space separated paths the update never touches |

`/etc/batohub/panel.conf` (mode 0600, written by BaToHub):

| Key | Description |
| --- | --- |
| `PANEL` | Panel identifier, for example `rebecca` |
| `PANEL_PORT` | Port recorded for the panel at selection time |
| `PANEL_PATH` | Installation path recorded at selection time |
| `PANEL_DOMAIN` | Domain read from the panel configuration when one is present |
| `INSTALLED_AT` | Date and time the panel was selected |

Changing the managed panel from Settings rewrites `PANEL` and does not remove or modify the previous panel.

## 16. Backup, restore and import

A backup archive contains:

- `/etc/batohub` in full;
- `/var/lib/batohub` in full, excluding the backup directory itself;
- `/var/log/batohub` in full;
- the configuration and data paths declared by the selected panel in `panel.json`;
- the certificate and template directories BaToHub manages for that panel;
- a metadata file, `BaToHub-backup.meta`, recording the BaToHub version, the panel, the panel version, the timestamp and the list of paths.

Files are stored as `${BACKUP_DIR}/<timestamp>.tar.gz` with a `.sha256` sidecar, mode 0600, owner root. Rotation keeps the newest `BACKUP_KEEP` archives.

Restore:

1. The SHA-256 sidecar is verified.
2. Every archive member is checked against the path list in the metadata; anything undeclared aborts the restore.
3. A safety backup of the current state is created.
4. The archive is extracted into a temporary directory and copied into place path by path. Files outside the declared paths are never touched.

Import accepts an archive from another location, copies it into the backup directory, generates a checksum when the source has none, verifies it and then restores it through the same transaction.

Commands: `BaToHub --backup`, `BaToHub --restore FILE`, or the Backup, Restore and Import backup entries in the menu.

## 17. Self-update

```bash
BaToHub --update
```

The update:

1. Fetches the configured branch with `git` when it is available, otherwise downloads `https://github.com/<repo>/archive/refs/heads/main.tar.gz`. Both paths use HTTPS with certificate validation.
2. Compares the remote `VERSION` with the installed version and refuses a downgrade unless `--force` is given.
3. Creates a backup of the state directories and a snapshot of the installation tree.
4. Validates the downloaded tree with `bash -n` before anything is replaced.
5. Synchronises files, leaving the protected paths alone: `/etc/batohub/batohub.conf`, `/etc/batohub/panel.conf`, `/var/lib/batohub`, `/var/log/batohub` and every path listed in `USER_MANAGED_PATHS`.
6. Validates every panel and tool interface, then rebuilds and verifies the integrity manifest.
7. Restores the snapshot of the previous tree when verification fails.

## 18. Security model

Implemented:

- `set -Eeuo pipefail` in every executable; quoted expansions throughout.
- No `eval`, no execution of downloaded text, no pipe from `curl` into a shell. Installers are downloaded to a temporary file, checked for size, and run as `bash <file> <action>`.
- HTTPS with certificate validation (`--proto '=https' --tlsv1.2`) for every download, and a refusal to fetch over plain HTTP.
- Path validation for panel names, domains, addresses and template targets, with refusals for paths outside the directories BaToHub manages.
- All temporary files and directories created with `mktemp`.
- File locking with `flock` around configuration and state writes, and atomic writes through a temporary file in the destination directory followed by a rename.
- Mode 0600 for configuration and state files, 0750 for `/etc/batohub`, `/var/lib/batohub` and `/var/log/batohub`.
- Private keys written with mode 0600 and never printed.
- One certificate directory per panel with an ownership marker, so a panel can never adopt another panel's certificate storage.
- Log lines record actions and outcomes; passwords, keys, tokens and licence-free configuration values are not logged.
- Integrity manifest with SHA-256 for every shipped file, verified on demand and after every update.

Limitations, stated plainly:

- A local root user can modify or delete any file. The integrity manifest detects the change; it does not prevent it.
- The update mechanism trusts the GitHub repository over HTTPS and the checksum of the release archive. GPG signing is supported by `scripts/build-release.sh` when the maintainer supplies a key; when no key is supplied the release carries SHA-256 checksums only, and no signature is claimed. See [SECURITY.md](SECURITY.md).
- acme.sh is trusted as the certificate client. BaToHub does not audit it.
- Panels are installed by their own official installers, downloaded over HTTPS and executed as they are supplied. BaToHub does not review that code.
- BaToHub does not run automated penetration testing and makes no claim about it.
- Where a panel exposes no documented integration point, BaToHub reports that and stops instead of guessing at database schemas.

## 19. Logging and troubleshooting

Logs are appended to `/var/log/batohub/batohub.log` with a timestamp on every line. The Logs view in the server menu prints the last eighty lines.

Common situations:

| Symptom | What to check |
| --- | --- |
| `certificate issuance failed` | The A record for the domain, port 80 availability, and the acme.sh output in the log |
| `Port 80 is already in use` | The message names the current listener; stop that service or issue with DNS-01 outside BaToHub |
| `Service X is not registered with systemd` | The panel is installed but has no systemd unit, so nothing was restarted |
| `integrity: manifest missing` | Run `BaToHub --rebuild-integrity` |
| `integrity: mismatched files detected` | `BaToHub --check` lists the files that differ from the manifest |
| A panel is not detected | Check the path, the systemd unit and the listening port against `panel.json` |
| The remote version is older | Downgrades are refused by design; use `--force` only when you intend to downgrade |

Useful commands:

```bash
BaToHub --status
BaToHub --check
BaToHub --validate
BaToHub --panel rebecca logs
tail -n 200 /var/log/batohub/batohub.log
```

## 20. Uninstall

```bash
BaToHub --uninstall
```

The uninstaller lists exactly what it will remove, requires the confirmation phrase, and removes only:

- `/opt/batohub`
- `/etc/batohub`
- `/var/lib/batohub`
- `/var/log/batohub`
- the global command link, and only when it points at `/opt/batohub/bin/batohub`

Backup archives can be moved to `/var/backups/batohub-<timestamp>` instead of being deleted. Panels, their databases, their configuration and certificates outside BaToHub state storage are never removed. `bin/uninstall --yes` skips the prompt for automation, and `--keep-backups` keeps archives without asking.

## 21. License

BaToHub is released under the GNU General Public License, version 3. The full text is in [LICENSE](LICENSE). The license text is used unmodified: no additional clauses, no exceptions and no dual licensing.

## 22. Modification and redistribution policy

Any use, modification, fork, sublicense or redistribution must comply with GPL-3.0 in full, and must preserve the original copyright notice, the project name BaToHub and the original repository URL. Custom or proprietary versions are not permitted under this license. Anyone who needs a custom or private version must contact support through the channel listed below.

## 23. Support and contact

Support, bug reports and feature requests: **@DatPHP**

Before asking for help, include:

- the output of `BaToHub --version`, `BaToHub --status` and `BaToHub --check`;
- the panel name and version;
- the exact command that failed and the error message;
- the last lines of `/var/log/batohub/batohub.log`.

Keep private keys, passwords and tokens out of reports.

See [SUPPORT.md](SUPPORT.md) for the support scope, [CONTRIBUTING.md](CONTRIBUTING.md) for how to submit changes, [SECURITY.md](SECURITY.md) for vulnerability reports and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for conduct expectations. The changelog is in [CHANGELOG.md](CHANGELOG.md).

## 24. Credits and copyright

BaToHub is developed and maintained by the BaToHub project. Copyright belongs to the project contributors and is distributed under the terms of GPL-3.0. Panel names, project names and trademarks belong to their respective owners; BaToHub is not affiliated with them.
