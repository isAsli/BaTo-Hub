#!/usr/bin/env bash
set -Eeuo pipefail

# Release builder.
#
# Modes:
#   --write-manifest   Recompute version, panel, tool and file hashes in
#                      manifest.json. No archive is created.
#   (default)          Build the release archive, compute its SHA-256, write the
#                      archive hash into manifest.json, write a .sha256 sidecar,
#                      and sign manifest.json when a signing key is available.
#
# Signing is optional. When no key is supplied the archive is published with its
# SHA-256 checksum, which is documented in SECURITY.md as the verification
# method. A signature is never claimed when one was not produced.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MANIFEST="manifest.json"
GPG_KEY_ID="${GPG_KEY_ID:-}"
WRITE_MANIFEST_ONLY=0

usage() {
  printf 'Usage: %s [--write-manifest] [--gpg-key KEY_ID]\n' "$0"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --write-manifest) WRITE_MANIFEST_ONLY=1 ;;
  --gpg-key)
    shift
    GPG_KEY_ID="${1:-}"
    [[ -n "$GPG_KEY_ID" ]] || {
      printf 'ERROR: --gpg-key needs a key id.\n' >&2
      exit 2
    }
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

version="$(tr -d '[:space:]' <VERSION)"
package="BaToHub-${version}.zip"
release_url="https://github.com/isAsli/BaTo-Hub/releases/tag/v${version}"
package_url="https://github.com/isAsli/BaTo-Hub/releases/download/v${version}/${package}"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'ERROR: python3 is required to write the manifest.\n' >&2
  exit 1
fi

write_manifest() {
  local archive_sha="${1:-}" archive_name="${2:-}"
  python3 - "$MANIFEST" "$version" "$release_url" "$package_url" "$archive_sha" "$archive_name" <<'PY'
import hashlib
import json
import os
import sys

manifest_path, version, release_url, package_url, archive_sha, archive_name = sys.argv[1:7]

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()

manifest["version"] = version
manifest["app"] = "BaToHub"
manifest["release_url"] = release_url
manifest["package"] = package_url

panels = []
for name in sorted(os.listdir("panels")):
    metadata = os.path.join("panels", name, "panel.json")
    if not os.path.isfile(metadata):
        continue
    with open(metadata, encoding="utf-8") as handle:
        panel = json.load(handle)
    panels.append({
        "name": panel["name"],
        "display_name": panel["display_name"],
        "version": panel["version"],
    })
manifest["panels"] = panels

tools = []
if os.path.isdir("tools"):
    for name in sorted(os.listdir("tools")):
        metadata = os.path.join("tools", name, "tool.json")
        if not os.path.isfile(metadata):
            continue
        with open(metadata, encoding="utf-8") as handle:
            tool = json.load(handle)
        tools.append({
            "name": tool["name"],
            "display_name": tool["display_name"],
            "version": tool["version"],
        })
manifest["tools"] = tools

# manifest.json cannot contain its own hash, so it is not part of the map.
managed = ["VERSION", "install.sh"]
for base in ("bin", "core", "lib", "panels", "tools", "security", "config", "scripts"):
    for current, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if d not in {".git", "__pycache__"})
        for name in sorted(files):
            managed.append(os.path.join(current, name))

manifest["files"] = {path: sha256(path) for path in sorted(set(managed)) if os.path.isfile(path)}

if archive_sha:
    manifest["sha256"] = archive_sha
    manifest["package_file"] = archive_name
elif "sha256" in manifest and not archive_name:
    manifest.pop("sha256", None)
    manifest.pop("package_file", None)

with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=False)
    handle.write("\n")
PY
}

if [[ "$WRITE_MANIFEST_ONLY" -eq 1 ]]; then
  write_manifest "" ""
  printf 'manifest.json updated for version %s\n' "$version"
  exit 0
fi

for command_name in zip sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: %s is required to build a release archive.\n' "$command_name" >&2
    exit 1
  fi
done

printf 'Building %s\n' "$package"
rm -f -- "$package" "${package}.sha256" "${MANIFEST}.asc"
zip -r -q "$package" . \
  -x '.git/*' \
  -x '.github/*' \
  -x 'node_modules/*' \
  -x '__pycache__/*' \
  -x '*.pyc' \
  -x '*.swp' \
  -x '.DS_Store'

archive_sha="$(sha256sum "$package" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha" "$package" >"${package}.sha256"
printf 'SHA-256: %s\n' "$archive_sha"

write_manifest "$archive_sha" "$package"

signing_status="not performed"
if [[ -n "$GPG_KEY_ID" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    printf 'ERROR: gpg is not installed but a signing key was requested.\n' >&2
    exit 1
  fi
  if gpg --batch --no-tty --yes --armor --default-key "$GPG_KEY_ID" --detach-sign "$MANIFEST"; then
    if gpg --batch --no-tty --verify "${MANIFEST}.asc" "$MANIFEST"; then
      signing_status="signed and verified with key ${GPG_KEY_ID}"
    else
      printf 'ERROR: the manifest signature could not be verified.\n' >&2
      exit 1
    fi
  else
    printf 'ERROR: signing manifest.json failed.\n' >&2
    exit 1
  fi
else
  printf 'No signing key was supplied. Publishing SHA-256 checksums only.\n'
fi

printf 'Signing: %s\n' "$signing_status"
printf 'Archive: %s\n' "$package"
printf 'Checksum: %s.sha256\n' "$package"
printf 'Manifest: %s\n' "$MANIFEST"
