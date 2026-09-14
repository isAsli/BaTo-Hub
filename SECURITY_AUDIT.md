# Security Audit

Scope: BaToHub panel-first shell source tree at version 0.0.2.

Files audited:
- install.sh
- bin/batohub
- bin/uninstall
- core/main.sh
- core/module_loader.sh
- core/panel_manager.sh
- core/ssl_manager.sh
- core/template_manager.sh
- core/backup_manager.sh
- core/update.sh
- lib/common.sh
- security/integrity.sh
- panels/rebecca/panel.json
- panels/rebecca/module.sh
- panels/rebecca/ssl/module.sh
- panels/rebecca/templates/module.sh
- panels/rebecca/templates/subscription/index.html
- panels/rebecca/update/module.sh
- panels/rebecca/menu/module.sh
- panels/pasarguard/panel.json
- panels/pasarguard/module.sh
- panels/pasarguard/ssl/module.sh
- panels/pasarguard/templates/module.sh
- panels/3x-ui/panel.json
- panels/3x-ui/module.sh
- panels/3x-ui/ssl/module.sh
- panels/3x-ui/templates/module.sh
- config/batohub.conf
- manifest.json

## 1. Removed OpenLicense layer

### 1.1 License validation code no longer exists in the runtime flow
- Files: core/license.sh, core/main.sh, config/batohub.conf, manifest.json
- Severity: removed
- Root cause: previous release contained a centralized license validation layer; the project is now fully free and open source and that layer is removed.
- Status: removed from source, config, manifest, CI, and documentation.

### 1.2 No network call to a licensing server remains
- Files: core/license.sh, core/main.sh
- Severity: removed
- Root cause: network calls were previously used for activation checks; they are now absent.
- Status: grep confirms no remaining functional license path in shell sources.

## 2. Configuration and state storage

### 2.1 panel.conf and batohub.conf protection
- Files: config/batohub.conf, core/panel_manager.sh
- Severity: medium
- Root cause: protected config files must never be world-readable and must not be overwritten by update.
- Status: permissions are set to 600 with owner root:root and update restores protected paths from backup.

### 2.2 State directory permissions
- Files: lib/common.sh, core/backup_manager.sh
- Severity: low
- Root cause: /etc/batohub, /var/lib/batohub, /var/log/batohub must be mode 750 and owner root:root.
- Status: installer and backup manager enforce those permissions.

## 3. Panel isolation

### 3.1 SSL paths are panel-specific
- Files: panels/*/ssl/module.sh
- Severity: medium
- Root cause: SSL files must not be shared between panels in a way that affects other panels.
- Status: Rebecca SSL uses a panel-specific cert directory and renewal hook; other panels are stubs.

### 3.2 Template paths are panel-specific
- Files: panels/*/templates/module.sh
- Severity: medium
- Root cause: applying a template for one panel must not change another panel.
- Status: each panel uses its own template module and does not touch other panel paths.

### 3.3 Pre-modification backup for template changes
- Files: panels/rebecca/templates/module.sh
- Severity: low
- Root cause: template application should be reversible.
- Status: existing template is backed up before modification.

## 4. Backup, restore, and import

### 4.1 Checksum verification
- Files: core/backup_manager.sh
- Severity: high
- Root cause: restore must verify integrity before applying.
- Status: restore and import verify checksum when available.

### 4.2 Transactional restore
- Files: core/backup_manager.sh
- Severity: high
- Root cause: partial extraction must not overwrite live state.
- Status: restore extracts to a temp directory before moving files into place.

### 4.3 Automatic safety backup before restore
- Files: core/backup_manager.sh
- Severity: high
- Root cause: restore operations can overwrite current state.
- Status: restore creates a safety backup before proceeding.

### 4.4 Rotation
- Files: core/backup_manager.sh
- Severity: low
- Root cause: unlimited backups are not acceptable.
- Status: rotation keeps the configured number of backups and removes old ones.

## 5. Self-update

### 5.1 Protected paths
- Files: core/update.sh
- Severity: high
- Root cause: update must not overwrite panel.conf, batohub.conf, or user data.
- Status: protected paths are listed and restored from the pre-update backup.

### 5.2 Verification and rollback
- Files: core/update.sh
- Severity: high
- Root cause: a failed update must not leave the system in a broken managed state.
- Status: shell syntax is checked on updated files before promotion and rollback is attempted on failure.

### 5.3 Diff visibility
- Files: core/update.sh
- Severity: low
- Root cause: users should know what changed during update.
- Status: added/removed/changed files are printed after successful update.

## 6. Secure coding practices

### 6.1 Strict mode and quoting
- Files: all .sh files
- Severity: medium
- Root cause: unattended errors and unquoted expansions cause injection and mishandling.
- Status: set -euo pipefail is used and variables are quoted.

### 6.2 Temporary files
- Files: lib/common.sh, core/update.sh, core/backup_manager.sh
- Severity: medium
- Root cause: predictable temp files can lead to races and conflicts.
- Status: mktemp is used for temporary files and directories.

### 6.3 Shared state locking
- Files: lib/common.sh, panels/rebecca/ssl/module.sh, panels/rebecca/templates/module.sh
- Severity: medium
- Root cause: concurrent writes to .env or similar files can corrupt state.
- Status: flock is used around shared file writes where practical.

## 7. Contact and license hygiene

### 7.1 No contact handle in source code
- Files: all .sh files, .json files
- Severity: high
- Root cause: the project rule requires no Telegram handle or username in source code.
- Status: no contact handle appears in shell or manifest files; contact appears only in documentation.

### 7.2 License file
- Files: LICENSE
- Severity: medium
- Root cause: the project must ship GPL-3.0 with the unmodified license text.
- Status: LICENSE contains the full GPL-3.0 text.

## 8. Documentation integrity

### 8.1 Bilingual documentation
- Files: README.md, README.fa.md, SECURITY.md, SECURITY.fa.md, CONTRIBUTING.md, CONTRIBUTING.fa.md, SUPPORT.md, SUPPORT.fa.md, CODE_OF_CONDUCT.md, CODE_OF_CONDUCT.fa.md, CHANGELOG.md
- Severity: medium
- Root cause: documentation must be consistent across languages and must not contain AI-related wording, emojis, or marketing language.
- Status: documents were rewritten for v0.0.2 with the required sections and contact handle @DatPHP.

## 9. Testing summary

The following checks were performed before release:
- shellcheck on all shell files
- bash -n on all shell files
- shfmt formatting check
- grep for license-related functional references in source
- grep for contact handles in source
- panel.json validity check for every panel
- panel interface function check for every panel
- protected config isolation check
- backup, restore, and import logic review
- self-update protected path and rollback review

All checks passed for the committed tree.

## 10. Limitations

- Rebecca SSL depends on Certbot and port 80 availability.
- PasarGuard and 3X-UI are stubs in this release and do not implement SSL or templates.
- Self-update depends on git availability for full fidelity; without git it applies a safer fallback with reduced diff reporting.
- No connection to any licensing server exists in this release.
- Root access can still modify local files; integrity checks detect tampering but do not make the system physically immutable.
