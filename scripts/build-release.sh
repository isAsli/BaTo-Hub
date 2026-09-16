#!/usr/bin/env bash
set -Eeuo pipefail

# Release builder.
#
# Modes:
#   --write-manifest        Recompute version, panel, tool and file hashes in
#                           manifest.json. No archive is created.
#   --verify-manifest       Compare manifest.json with the working tree. Nothing
#                           is written; exits non-zero on any difference.
#   --verify-archive FILE   Compare an archive with manifest.json, member by
#                           member. Nothing is written.
#   (default)               Build the release archive, compute its SHA-256,
#                           record the archive hash and the hash of every
#                           shipped file in manifest.json, write the .sha256
#                           sidecar, and sign manifest.json when a signing key
#                           is available.
#
# A release contains exactly the files that git tracks: an untracked or
# unreviewed file in the working tree can never reach a release, and the build
# refuses to run from a tree with uncommitted changes unless --allow-dirty is
# passed. manifest.json is published as its own release asset and is not a
# member of the archive, so the archive contains exactly the files recorded in
# the manifest and the two can be compared member by member.
#
# Signing is optional. When no key is supplied the archive is published with its
# SHA-256 checksum, which is documented in SECURITY.md as the verification
# method. A signature is never claimed when one was not produced.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MANIFEST="manifest.json"
GPG_KEY_ID="${GPG_KEY_ID:-}"
MODE="build"
VERIFY_TARGET=""
ALLOW_DIRTY=0

usage() {
  printf 'Usage: %s [--write-manifest | --verify-manifest | --verify-archive FILE]\n' "$0"
  printf '          [--gpg-key KEY_ID] [--allow-dirty]\n'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --write-manifest) MODE="write" ;;
  --verify-manifest) MODE="verify-manifest" ;;
  --verify-archive)
    shift
    VERIFY_TARGET="${1:-}"
    MODE="verify-archive"
    [[ -n "$VERIFY_TARGET" ]] || {
      printf 'ERROR: --verify-archive needs an archive path.\n' >&2
      exit 2
    }
    ;;
  --gpg-key)
    shift
    GPG_KEY_ID="${1:-}"
    [[ -n "$GPG_KEY_ID" ]] || {
      printf 'ERROR: --gpg-key needs a key id.\n' >&2
      exit 2
    }
    ;;
  --allow-dirty) ALLOW_DIRTY=1 ;;
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
  printf 'ERROR: python3 is required to write and verify the manifest.\n' >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'ERROR: the file list of a release comes from git; run this script from a checkout.\n' >&2
  exit 1
fi

file_list="$(mktemp "${TMPDIR:-/tmp}/batohub.release.XXXXXX")"
cleanup() { rm -f -- "$file_list"; }
trap cleanup EXIT

# The files a release consists of, in a stable order. Repository-only content
# (.github), the manifest itself and previous build outputs are not shipped.
shipped_files() {
  git ls-files -- . | grep -v -E '^(\.github/|manifest\.json$|BaToHub-.*\.zip)' || true
}

shipped_files >"$file_list"
shipped_count="$(wc -l <"$file_list" | tr -d '[:space:]')"
if [[ "$shipped_count" -eq 0 ]]; then
  printf 'ERROR: the shipped file list is empty; this is not a release tree.\n' >&2
  exit 1
fi

write_manifest() {
  local archive_sha="${1:-}" archive_name="${2:-}"
  python3 - "$MANIFEST" "$version" "$release_url" "$package_url" "$archive_sha" "$archive_name" "$file_list" <<'PY'
import hashlib
import json
import os
import sys

manifest_path, version, release_url, package_url, archive_sha, archive_name, list_path = sys.argv[1:8]

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


with open(list_path, encoding="utf-8") as handle:
    shipped = [line.strip() for line in handle if line.strip()]

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

# Every shipped file is recorded, so the manifest describes the archive
# completely. manifest.json cannot record its own hash and is not shipped.
manifest["files"] = {path: sha256(path) for path in shipped if os.path.isfile(path)}

if archive_sha:
    manifest["sha256"] = archive_sha
    manifest["package_file"] = archive_name
else:
    manifest.pop("sha256", None)
    manifest.pop("package_file", None)

with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=False)
    handle.write("\n")
PY
}

verify_manifest() {
  python3 - "$MANIFEST" "$file_list" <<'PY'
import hashlib
import json
import sys

manifest_path, list_path = sys.argv[1:3]

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)

with open(list_path, encoding="utf-8") as handle:
    shipped = [line.strip() for line in handle if line.strip()]

recorded = manifest.get("files", {})
problems = []


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            value.update(block)
    return value.hexdigest()


for path in shipped:
    if path not in recorded:
        problems.append(f"the manifest does not record {path}")
        continue
    if digest(path) != recorded[path]:
        problems.append(f"the manifest hash does not match {path}")

for path in sorted(set(recorded) - set(shipped)):
    problems.append(f"the manifest records {path}, which is not part of the release")

for item in problems:
    print(f"FAIL [release manifest] {item}", file=sys.stderr)

if problems:
    raise SystemExit(1)

print(f"ok   manifest.json covers all {len(shipped)} shipped files")
PY
}

verify_archive() {
  local archive="$1"
  python3 - "$MANIFEST" "$archive" <<'PY'
import hashlib
import json
import sys
import zipfile

manifest_path, archive_path = sys.argv[1:3]

with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)

recorded = manifest.get("files", {})
problems = []

with zipfile.ZipFile(archive_path) as archive:
    members = [name for name in archive.namelist() if not name.endswith("/")]
    for name in members:
        if name not in recorded:
            problems.append(f"the archive contains {name}, which the manifest does not record")
            continue
        if hashlib.sha256(archive.read(name)).hexdigest() != recorded[name]:
            problems.append(f"the manifest hash does not match the archive member {name}")

for name in sorted(set(recorded) - set(members)):
    problems.append(f"the manifest records {name}, which the archive does not contain")

value = hashlib.sha256()
with open(archive_path, "rb") as handle:
    for block in iter(lambda: handle.read(65536), b""):
        value.update(block)
if manifest.get("sha256") and manifest["sha256"] != value.hexdigest():
    problems.append("the archive hash recorded in the manifest does not match the archive")

for item in problems:
    print(f"FAIL [release archive] {item}", file=sys.stderr)

if problems:
    raise SystemExit(1)

print(f"ok   all {len(members)} archive members match manifest.json")
PY
}

case "$MODE" in
verify-manifest)
  verify_manifest
  exit $?
  ;;
write)
  write_manifest "" ""
  printf 'manifest.json updated for version %s (%s shipped files)\n' "$version" "$shipped_count"
  exit 0
  ;;
verify-archive)
  [[ -f "$VERIFY_TARGET" ]] || {
    printf 'ERROR: archive not found: %s\n' "$VERIFY_TARGET" >&2
    exit 1
  }
  verify_archive "$VERIFY_TARGET"
  exit $?
  ;;
esac

for command_name in zip sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: %s is required to build a release archive.\n' "$command_name" >&2
    exit 1
  fi
done

if [[ "$ALLOW_DIRTY" -ne 1 ]]; then
  # A release is built from committed files only, so the packaged content is
  # always reviewable in the repository.
  if dirty="$(git status --porcelain)" && [[ -n "$dirty" ]]; then
    printf 'ERROR: the working tree has uncommitted changes:\n' >&2
    printf '%s\n' "$dirty" >&2
    printf 'Commit or stash them, or pass --allow-dirty for a test build.\n' >&2
    exit 1
  fi
fi

printf 'Building %s from %s tracked file(s)\n' "$package" "$shipped_count"
rm -f -- "$package" "${package}.sha256" "${MANIFEST}.asc"

zip -q -X "$package" -@ <"$file_list"

archive_sha="$(sha256sum "$package" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha" "$package" >"${package}.sha256"
printf 'SHA-256: %s\n' "$archive_sha"

write_manifest "$archive_sha" "$package"
verify_archive "$package"

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
