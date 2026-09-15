# BaToHub 0.0.3

This release completes the panel-first architecture started in 0.0.2, adds two
panels and one tool, and removes the last remnants of the earlier licensing
design.

## Added

- Marzban panel: detection, version, status, official installer and updater,
  logs, SSL, subscription template and menu.
- VPN-UI panel: independent install path, its own service, bare address
  certificate support and subscription template staging.
- Foxima tool module with prerequisite checks, an installation wizard, a
  recorded install path and removal limited to a BaToHub-recorded installation.
- `BaToHub --panel NAME CMD` command interface covering detect, version, status,
  install, uninstall, ssl-issue, ssl-renew, ssl-status, template-apply,
  template-remove, update and logs.
- `BaToHub --validate`, which loads every panel and tool and checks the required
  interface functions.
- `BaToHub --check` and `BaToHub --rebuild-integrity` for the integrity manifest.
- `scripts/checks.sh` and `scripts/checks_text.py` for syntax, shellcheck,
  formatting, metadata, interface, documentation and text hygiene checks, used
  by CI and runnable locally.
- `scripts/verify-install.sh` for an isolated functional install on a disposable
  prefix, and `scripts/container-verify.sh` for installation into a clean
  distribution userland.
- `BaToHub-backup.meta`, which lists every path a backup archive may contain.
- English and Persian documentation set: README, SECURITY, CONTRIBUTING, SUPPORT
  and CODE_OF_CONDUCT.

## Changed

- PasarGuard and 3X-UI are fully implemented rather than interface scaffolds.
- `core/module_loader.sh` is replaced by `core/panel_loader.sh`; only one loader
  exists.
- The panel directory is the single source of truth:
  `panels/<name>/{panel.json,module.sh,ssl,templates,update,menu}`.
- Certificates are stored per panel under
  `/var/lib/batohub/panels/<panel>/ssl/<target>/` with an ownership marker.
- Template replacement copies the previous file into BaToHub state storage
  first.
- The installer is idempotent and preserves an existing configuration.

## Removed

- The licensing layer in full: `core/license.sh`, every call to it, and every
  reference to an activation or validation server. BaToHub has no paid tier and
  makes no outbound validation call.
- References to a legacy support handle that is no longer part of the project.

## Fixed

- Grouped `find` expressions in the integrity step, so file selection is
  reliable.
- Restore refuses archive members that the metadata does not declare.
- Configuration and state writes are serialised with `flock` and atomic renames.
- Certificate and template removal refuse paths outside the directories BaToHub
  manages.

## Security

- Downloads require HTTPS with certificate validation.
- No `eval`, no execution of downloaded text, and no pipe from `curl` into a
  shell.
- Private keys are written with mode 0600 and are never printed.
- Configuration and state files are mode 0600; `/etc/batohub`,
  `/var/lib/batohub` and `/var/log/batohub` are mode 0750.

## Verification

Verified before release:

- `bash scripts/checks.sh` passes.
- `bash scripts/verify-install.sh` passes: install, documented commands, the
  panel interface for all five panels, backup and restore, panel selection and
  uninstall.
- `bash scripts/container-verify.sh ubuntu:22.04` and
  `bash scripts/container-verify.sh debian:12` pass: installation into a clean
  distribution userland, followed by the documented commands, tamper detection
  and uninstall.

## Notes on 0.0.2

v0.0.2 is marked as a pre-release. It shipped PasarGuard and 3X-UI as interface
scaffolds without complete SSL, template, update and menu workflows, and
container installation verification had not been performed. It is superseded by
this release.
