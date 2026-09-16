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
- Integrity manifest with a SHA-256 entry for every shipped file, and the optional INTEGRITY_HARD_FAIL setting that refuses to open the interface when a file differs from the manifest.
- The tagged-source fallback is refused unless BATOHUB_ALLOW_UNVERIFIED_FALLBACK=1 is set, because no checksum is published for that archive.
- Backup, restore and import with a checksummed archive and a member allowlist, transactional restore and a safety backup.
- Self-update from a pinned release with SHA-256 verification, protected paths, an installation snapshot and rollback.
- No telemetry, and no outbound call other than the downloads and the version listings the operator requests.

Git history

The history was rewritten for 0.0.4. Two commits carried a co-author trailer naming a third-party development tool, and one commit message referred to that tool's involvement; those lines were removed, and the tags v0.0.1, v0.0.2 and v0.0.3 were moved onto the rewritten history. Commit identifiers from before the rewrite no longer resolve.

Verification performed before publication

- scripts/checks.sh: shell syntax, shellcheck, shfmt formatting, JSON metadata, the panel and tool interfaces, version consistency, the release manifest, the git history and the text hygiene rules.
- scripts/build-release.sh --verify-archive: every archive member against manifest.json, and the archive against its SHA-256 sidecar.
- scripts/verify-install.sh: an isolated installation that exercises the documented commands, the panel interface, the version commands, templates, backup, restore, panel selection and uninstall.
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
