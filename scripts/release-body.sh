#!/usr/bin/env bash
set -Eeuo pipefail

# Release body generator.
#
# Prints the body of a GitHub release for the version in VERSION. Two rules are
# enforced here rather than in the workflow:
#
#   1. Only assets that are actually attached are listed. The detached
#      signature of manifest.json appears only when a signing key was
#      configured and the signature was produced, which the caller reports
#      through --signed.
#   2. The text describes the current properties of the project only. It makes
#      no claim that the release does not verify.
#
# Usage: bash scripts/release-body.sh [--signed yes|no]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNED="no"

usage() {
  printf 'Usage: %s [--signed yes|no]\n' "$0"
  printf '  --signed yes  the detached signature of manifest.json is attached\n'
  printf '  --signed no   the release carries SHA-256 checksums only (default)\n'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --signed)
    shift
    SIGNED="${1:-}"
    case "$SIGNED" in
    yes | no) ;;
    *)
      printf 'ERROR: --signed takes yes or no, not %s\n' "${SIGNED:-<empty>}" >&2
      exit 2
      ;;
    esac
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'ERROR: unknown option: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

version="$(tr -d '[:space:]' <"${ROOT}/VERSION")"
package="BaToHub-${version}.zip"

asset_lines() {
  printf '%s\n' "- ${package}: the complete release tree."
  printf '%s\n' "- ${package}.sha256: the SHA-256 of the archive."
  printf '%s\n' "- manifest.json: the version, the panel and tool list, and a SHA-256 for every file of the archive."
  if [[ "$SIGNED" == "yes" ]]; then
    printf '%s\n' "- manifest.json.asc: the detached signature of manifest.json."
  fi
}

signature_statement() {
  if [[ "$SIGNED" == "yes" ]]; then
    printf '%s\n' "The manifest is signed, and the signature is attached to this release."
  else
    printf '%s\n' "No signing key is configured for this release, so the release carries SHA-256 checksums and no signature is claimed."
  fi
}

cat <<EOF
BaToHub ${version}

Assets

$(asset_lines)

$(signature_statement)

What is in this release

- Five panel modules: Rebecca, Marzban, PasarGuard, 3X-UI (Sanaei) and VPN-UI. Each one declares its own metadata, install path, service name, SSL method, template method and update method, and implements the full panel interface.
- Panel version detection and selection. Each panel lists the releases published by its own repository, and installs the release the operator chooses through that panel's own official installer. The newest stable release is the default, a development channel is offered where the installer declares one, and a panel whose installer always resolves the newest release is reported as not supporting version pinning rather than being pinned silently.
- The installed version is read back after the operation and the change is recorded with a timestamp in /var/log/batohub/versions.log and in the panel log.
- One tool module: Foxima, with detection, install, update, status, logs, configuration guidance, and removal limited to the changes BaToHub manages.
- The installer makes every entry point under bin executable. The management bot is started by its own systemd unit, so its mode is set from the installer rather than taken from the archive.
- Integrity manifest with a SHA-256 entry for every shipped file, and the optional INTEGRITY_HARD_FAIL setting that refuses to open the interface when a file differs from the manifest.
- The tagged-source fallback is refused unless BATOHUB_ALLOW_UNVERIFIED_FALLBACK=1 is set, because no checksum is published for that archive.
- Backup, restore and import with a checksummed archive and a member allowlist that rejects absolute paths, parent traversal, undeclared members, and links whose location or target leaves the destination roots, transactional restore and a safety backup.
- Self-update from a pinned release with SHA-256 verification, protected paths, an installation snapshot and rollback.
- Servers and nodes: registration, listing, status, restart and deregistration of remote panel nodes through each panel's own API, with one record per node, the identifier the panel assigned recorded, and no write on the remote machine.
- Multiple domains per panel, each registered with its purpose, with a wildcard name switching to DNS validation, a reload hook registered at issuance, and revocation with a recorded outcome.
- Backup delivery to a Telegram chat on an hourly, daily or weekly schedule, with splitting of a large archive, a ledger of what was delivered, and a token that never reaches a command line or a log.
- Migration between panels: accounts read from one panel and created on another through the APIs of both, with a preview, a backup of both panels before the write, a verification of the result, and a report of every account that could not be migrated. The source receives no write.
- Server tools: firewall rules, fail2ban jails and bans, BBR and TCP tuning, system limits, time zone and NTP, each reporting the current state before a change.
- Docker: detection of whether a panel runs in a container, from a Compose stack or as a system service, with status, logs, restart, resource counters and image update following the detected mode.
- Alerts: nine conditions covering panel state, nodes, certificates, an outdated panel version, disk, memory, CPU load, a stale backup and a failed update, delivered to Telegram, by email or to a webhook, with per-alert thresholds and cooldowns, and nothing enabled until an operator enables it.
- Accounts and roles: several operator accounts with hashed passwords, six roles and twenty-two permissions, checked when the menu is built and again when an action runs, with every action recorded. BaToHub admin login NAME compares a password with the stored hash and reports the result, so a stored password has a verification path.
- Reports: ten reports rendered on screen or exported as CSV or JSON, with a retention policy for the exports.
- Telegram bot: remote operation with thirteen commands, each mapped to a BaToHub account that holds the permissions that command needs, an unlisted user id refused without a reply, and every command and refusal recorded.
- No telemetry, and no outbound call other than the downloads and the version listings the operator requests.

Git history

The history was rewritten for 0.0.4. Two commits carried a co-author trailer naming a third-party development tool, and one commit message referred to that tool's involvement; those lines were removed, and the tags v0.0.1, v0.0.2 and v0.0.3 were moved onto the rewritten history. Commit identifiers from before the rewrite no longer resolve.

Verification performed before publication

- scripts/checks.sh: shell syntax, shellcheck, shfmt formatting, JSON metadata, the panel and tool interfaces, version consistency, the release manifest, the git history and the text hygiene rules.
- scripts/build-release.sh --verify-archive: every archive member against manifest.json, and the archive against its SHA-256 sidecar.
- scripts/verify-install.sh: an isolated installation that exercises the documented commands, the panel interface, the version commands, templates, backup, restore, crafted archives that must each be refused, panel selection, the node, certificate, delivery, migration, server, container, alert, account, report and bot command surfaces, and uninstall.
- scripts/integration-test.sh: local services that implement the endpoints each panel declares plus the Bot API methods, driven by the documented commands, covering authentication, request bodies, response parsing, error handling, state files and their permissions, node registration and deregistration, migration, delivery, alerts, accounts, reports and the management bot. The panels themselves are not installed, so a panel's own installer and protocol handling are not exercised.
- scripts/container-verify.sh ubuntu:22.04 and debian:12: installation into a clean distribution userland, followed by the documented commands, tamper detection and uninstall. The logs are attached to this workflow run as build artifacts.

Installation

\`\`\`
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
\`\`\`

The installer downloads this release asset, verifies its SHA-256 before anything is extracted, and installs from that pinned source.

Documentation

DOCS.md, README.md and SECURITY.md. The Persian documentation is in README.fa.md and DOCS.fa.md.

Known limitations

- Release archives are signed only when a signing key is configured in the release pipeline. Without one, the release carries SHA-256 checksums and no signature is claimed.
- The version list of a panel is read from the release list of that panel's own repository over the GitHub API, so it needs outbound HTTPS and is subject to that API's rate limits.
- The panel installers that BaToHub downloads are executed as supplied by their authors and are not reviewed by this project.
- Panel behaviour is verified structurally, not against live upstream panel installations.
See SECURITY.md for the security model.
EOF
