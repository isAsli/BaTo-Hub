# BaToHub

BaToHub is a central server management system written in Bash. It provides one entry point for managing server tools such as SSL, subscription templates, updates, and panel integrations through a modular plugin architecture.

The main command is `BaToHub`. It loads central configuration, performs integrity and license checks, and opens a hierarchical menu for the installed modules.

## Project description

BaToHub is designed to be installed once on a server and extended over time. The core manages configuration, logging, update verification, license validation, repair, and uninstall behavior. Modules add support for specific panels and tools without changing the core.

The repository is intended for Ubuntu 22.04 and Ubuntu 24.04 on amd64 and arm64. Other environments may work, but they are not the primary target.

## Feature list

Core:
- Central configuration and state directory
- Integrity manifest for managed files
- Logging to `/var/log/batohub`
- License validation hook
- Update system with manifest verification and rollback
- Server information and status
- Settings view
- Logs view
- Repair actions
- Uninstall with confirmation

Modules:
- Module discovery through `modules/<name>/module.json`
- Each module exposes install, uninstall, status, update, and menu behavior
- Disabled modules exist as labeled stubs, not broken code

Active integration:
- Rebecca
  - SSL installation, renewal, status, and removal
  - BaTo-Ui subscription template install, status, and removal
  - Rebecca status and BaToHub change removal

Not active in this release:
- PasarGuard
- Sanaei / 3X-UI

## Architecture

```
/opt/BaToHub/
  bin/
    batohub
    uninstall
  core/
    main.sh
    license.sh
    update.sh
    module_loader.sh
  lib/
    common.sh
  security/
    integrity.sh
  modules/
    <module>/
      module.json
      module.sh
      ...submodules...
  templates/
    <module>/
      ...
  VERSION
  manifest.json
```

System paths:
```
/etc/batohub/
  batohub.conf
  integrity.sha256
  license.json
  .license_key
/var/lib/batohub/
/var/log/batohub/
/usr/local/bin/BaToHub -> /opt/BaToHub/bin/batohub
```

Data flow:
1. `BaToHub` runs `bin/batohub`.
2. `bin/batohub` executes `core/main.sh`.
3. `main.sh` loads `lib/common.sh` and the configured config file.
4. `main.sh` calls license validation before opening the menu.
5. Module discovery loads every `modules/*/module.json`.
6. Active modules are loaded and exposed through the menu.

## Requirements

Operating systems:
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

Architectures:
- amd64
- arm64

Required commands:
- bash
- curl
- ca-certificates
- openssl
- unzip
- rsync
- python3
- whiptail
- dnsutils
- iproute2
- procps
- coreutils
- certbot

Optional:
- systemctl
- gpg

Root access is required for installation and for most management actions.

## Quick install

Run one command as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

What that does:
- Checks for root privileges
- Installs required system packages
- Creates the BaToHub directory structure under `/opt/BaToHub`
- Copies the source tree
- Writes central configuration
- Sets restrictive permissions
- Creates the `BaToHub` command
- Writes the integrity manifest

After install, run:

```bash
BaToHub
```

## Manual install

1. Download the source tree to a temporary location on the target server.
2. Run `install.sh` as root from that directory.
3. Verify that `/usr/local/bin/BaToHub` points to `/opt/BaToHub/bin/batohub`.
4. Run `BaToHub` and complete the license step if required.
5. For Rebecca integration, install the BaTo-Ui template from the Tools menu if Rebecca is present on the server.

Example steps:

```bash
apt-get update
apt-get install -y curl ca-certificates openssl unzip rsync python3 whiptail dnsutils iproute2 procps coreutils certbot
bash ./install.sh
BaToHub
```

## Post-install verification

Check the following after installation:
- `BaToHub` starts without errors
- The version reported by BaToHub matches `/opt/BaToHub/VERSION`
- `/etc/batohub/batohub.conf` is not world-readable
- `/etc/batohub/integrity.sha256` exists and passes `sha256sum -c`
- `/var/log/batohub/batohub.log` exists
- Disabled modules appear as unavailable and are not executed as active code

## Quick start

1. Run `BaToHub`.
2. Complete license validation if prompted.
3. Use the main menu to review update status, server info, and tools.
4. If Rebecca is installed, open Tools, then Rebecca, then install BaTo-Ui or manage SSL as needed.

## Command reference

| Command | Purpose |
| --- | --- |
| `BaToHub` | Open the central menu |
| `install.sh` | Install BaToHub as root |
| `bin/uninstall` | Remove BaToHub-managed files with confirmation |
| `sha256sum -c /etc/batohub/integrity.sha256` | Verify managed file integrity |

Menu actions are interactive. Destructive actions require an explicit confirmation phrase.

## Module system

Every module is a directory under `modules/<name>` with at least:
- `module.json`
- `module.sh`

`module.json` describes the module:

```json
{
  "name": "example",
  "version": "0.0.1",
  "description": "Example module",
  "status": "active",
  "path": "modules/example",
  "entry": "modules/example/module.sh",
  "dependencies": []
}
```

`module.sh` defines the interface functions used by the core:
- `<name>_menu`
- `<name>_install`
- `<name>_uninstall`
- `<name>_status`
- `<name>_update`

To add a new module:

1. Create `modules/<name>/module.json`.
2. Create `modules/<name>/module.sh`.
3. Implement the five interface functions.
4. If the module is active, set `"status": "active"` in its `module.json`.
5. Run `install.sh` or update the installation if needed.

Module discovery is automatic. The core does not need to be edited for every new module, as long as the naming convention is followed.

## Configuration reference

`/etc/batohub/batohub.conf` is sourced by the library. Relevant keys:

| Key | Description | Default |
| --- | --- | --- |
| `APP_NAME` | Application name | `BaToHub` |
| `APP_VERSION` | Application version | `0.0.1` |
| `LICENSE_API` | License validation endpoint | configured centrally |
| `LICENSE_PRODUCT` | Product identifier sent during validation | `batohub` |
| `SUPPORT` | Support contact shown on license failure | `@BaTo_Help` |
| `CHANNEL` | Channel contact | `@BaToHub` |
| `GITHUB_REPO` | GitHub repository used for release checks | `isAsli/BaTo-Hub` |
| `UPDATE_MANIFEST` | Remote manifest URL for updates | configured centrally |
| `MANIFEST_SIGNATURE` | Remote manifest signature URL | configured centrally |
| `INSTALL_DIR` | Main application directory | `/opt/batohub` |
| `STATE_DIR` | Persistent state directory | `/var/lib/batohub` |
| `CONFIG_DIR` | Configuration directory | `/etc/batohub` |
| `LOG_DIR` | Log directory | `/var/log/batohub` |
| `REBECCA_DIR` | Rebecca installation directory expected by BaToHub | `/opt/rebecca` |
| `TEMPLATE_ROOT` | Template root written into Rebecca env | `/opt/rebecca/bato-templates` |
| `GLOBAL_CMD_NAME` | Global command path created by installer | `/usr/local/bin/BaToHub` |

## Update mechanism

Updates are checked against a remote manifest. The expected flow is:
1. Download the manifest over HTTPS.
2. Verify the manifest signature with GPG.
3. Read version, package URL, and SHA-256 from the manifest.
4. Download the package.
5. Verify the package SHA-256.
6. Back up the current installation.
7. Extract the new package.
8. Replace managed files.
9. Rebuild the integrity manifest.
10. Verify the result.
11. Roll back if verification fails.

A manifest signature is required for update trust. If signature verification fails, update is skipped.

GitHub release information may be checked for reference, but it does not override the signed manifest flow.

## Security model

BaToHub uses several defensive measures:
- Centralized configuration with restrictive permissions
- Integrity manifest for managed files
- Locked writes for shared state where practical
- Temporary files created with `mktemp`
- Quoted variable expansions
- Input validation for prompts and module names
- Restricted permissions on private keys and sensitive config
- Logging in plain text without terminal escapes

Limitations:
- Root access can modify or delete local files. Integrity checks detect changes; they do not make the system physically immutable.
- Remote update trust depends on the signing key and the signature feed being correct.
- License validation depends on network access to the configured API.
- SSL management depends on Certbot and the availability of port 80 or an alternate challenge.
- Third-party updaters, such as the Rebecca binary updater, are executed only after download and are subject to the trust of their source.

Do not assume the system is unmodifiable. It is designed to detect tampering and to make unsafe changes more difficult.

## Logging and troubleshooting

Logs are written to:
```
/var/log/batohub/batohub.log
```

Each entry includes a timestamp and the action or error.

Common checks:
- Verify the installation path exists
- Verify permissions on `/etc/batohub` and `/var/log/batohub`
- Verify the integrity manifest
- Review the log file for recent errors
- Check whether required commands are installed
- Check whether port 80 is available before SSL operations
- Confirm the Rebecca `.env` file exists before template or SSL changes

If the update fails:
- The installer keeps a backup directory with a timestamp
- Review the log for the exact failure point
- Re-run update only after confirming the package source is trusted

## Uninstall

Run the uninstall command from the BaToHub menu or directly:

```bash
/opt/BaToHub/bin/uninstall
```

The uninstaller:
- Shows the files and directories that will be removed
- Asks for confirmation
- Optionally removes the BaToHub Certbot renewal hook
- Removes BaToHub-owned files
- Does not remove Rebecca itself

## License

BaToHub is provided with a centralized license validation model. The product identifier used for validation is `batohub`.

If license validation fails, contact the support address shown by the interface.

## Author contact

Support: @BaTo_Help
Channel: @BaToHub
