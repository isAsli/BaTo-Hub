# Changelog

All notable changes to BaToHub are recorded in this file. The format follows Keep a Changelog, and versions follow semantic versioning.

## [0.0.3]

### Added

- Marzban panel module with detection, status, version reporting, official installer, official updater, logs, SSL, subscription template and menu.
- VPN-UI panel module with independent paths, its own service, bare address certificate support and subscription template staging.
- Foxima tool module under `tools/foxima` with prerequisite checks, an installation wizard, recorded install path and safe removal of a BaToHub-recorded installation.
- `--panel NAME CMD` command interface for detect, version, status, install, uninstall, ssl-issue, ssl-renew, ssl-status, template-apply, template-remove, update and logs.
- `--validate` command that loads every panel and tool and verifies the required interface functions.
- `--check` and `--rebuild-integrity` commands for the integrity manifest.
- `scripts/checks.sh` and `scripts/checks_text.py`: syntax, shellcheck, formatting, metadata, interface, documentation and text hygiene checks, used by CI and available locally.
- Factual documentation set in English and Persian: README, SECURITY, CONTRIBUTING, SUPPORT and CODE_OF_CONDUCT, cross-linked from both READMEs.
- Backup metadata file `BaToHub-backup.meta` listing every path an archive may contain.

### Changed

- `core/module_loader.sh` was replaced by `core/panel_loader.sh`; only one loader exists.
- The panel directory is the single source of truth: `panels/<name>/{panel.json,module.sh,ssl,templates,update,menu}`.
- SSL certificates are stored per panel under `/var/lib/batohub/panels/<panel>/ssl/<target>/` with an ownership marker, so panels can never share certificate storage.
- Certificate registration with a panel updates only option names the panel already declares; unknown options are never appended, and when no option exists the operator is told which paths to configure.
- Subscription templates are copied into BaToHub state storage before being replaced.
- The self-update refuses downgrades, validates the downloaded tree with `bash -n`, validates every interface, rebuilds and verifies the integrity manifest, and restores the previous tree when verification fails.
- The installer is idempotent: it preserves an existing `/etc/batohub/batohub.conf`, backs up a pre-existing file at the global command path, resolves the release source locally or by HTTPS download, and validates every interface before finishing.
- The uninstaller removes only BaToHub-owned paths, can move backup archives to `/var/backups/batohub-<timestamp>`, and never touches a panel or its data.
- The integrity manifest uses grouped `find` expressions, is written atomically under `flock`, and treats a missing manifest as a hard failure.
- Menus show state indicators, ask for confirmation on destructive actions, report what to do next on failure, and log every action.
- Configuration keys are documented in `config/batohub.conf` and in the README configuration reference.

### Removed

- The license validation layer: `core/license.sh` and every reference to a validation server, activation, or licence checks. BaToHub is free software with no paid tier and no outbound validation call.
- References to a legacy support handle that is no longer part of the project.

### Fixed

- Panels could previously be loaded with hard-coded imports of another panel's module. Each module now resolves its own paths from `panel.json` through the loader.
- Backup creation used an `-o` expression without grouping, which made integrity and file selection unreliable.
- Restore previously accepted any archive member; it now refuses members that the archive metadata does not declare.
- Concurrency on configuration and state files is now serialised with `flock` and atomic renames.
- Template removal and certificate removal refuse paths outside the directories BaToHub manages.

### Security

- Downloads require HTTPS with certificate validation; plain HTTP is refused.
- No `eval`, no execution of remote text, and no pipe from `curl` into a shell. Official installers are downloaded to a temporary file and executed explicitly.
- Private keys are written with mode 0600 and are never printed.
- Configuration and state files are mode 0600; `/etc/batohub`, `/var/lib/batohub` and `/var/log/batohub` are mode 0750.

## [0.0.2]

### Added

- Panel-first layout with `panels/`, `core/panel_loader.sh` and shared helper libraries.
- First-run panel selection persisted to `/etc/batohub/panel.conf`.
- Backup, restore and import flows with checksums, transactional restore and rotation.
- Self-update from GitHub with protected paths and rollback.
- Integrity manifest and tamper reporting.
- English and Persian documentation set and a CI workflow.

### Changed

- Rebecca integration was rewritten around the panel interface, with SSL, template, status, update and change-removal actions.

### Removed

- The `modules/` tree, superseded by `panels/`.

### Notes

- v0.0.2 was published as a pre-release. PasarGuard and 3X-UI shipped as interface scaffolds without complete SSL, template, update and menu workflows, and container installation verification had not been performed, so the release was marked accordingly and superseded by v0.0.3.
