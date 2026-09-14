#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

PACKAGE="BaToHub-0.0.2.zip"
MANIFEST="manifest.json"
SIGNATURE="$MANIFEST.asc"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root."
    exit 1
  fi
}

prepare_manifest() {
  local sha256="$1"
  python3 - "$MANIFEST" "$sha256" "$PACKAGE" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
sha256 = sys.argv[2]
package_name = sys.argv[3]

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

manifest["sha256"] = sha256
manifest["package"] = "https://github.com/isAsli/BaTo-Hub/releases/download/v0.0.2/" + package_name

with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
}

compute_sha256() {
  SHA256=$(sha256sum "$PACKAGE" | awk '{print $1}')
  printf 'SHA256: %s\n' "$SHA256"
}

verify_signature() {
  if ! gpg --batch --no-tty --verify "$SIGNATURE" "$MANIFEST" 2>&1; then
    err "Signature verification failed for $MANIFEST"
    exit 1
  fi
  ok "Signature verified for $MANIFEST"
}

if [ "$#" -lt 1 ]; then
  err "Usage: $0 <gpg_key_id>"
  exit 1
fi

KEY_ID="$1"

need_root

info "Building release package: $PACKAGE"

rm -f "$PACKAGE" "$SIGNATURE"

zip -r "$PACKAGE" . -x "*.git*" -x "__pycache__/*" -x "*.swp" -x ".DS_Store"

compute_sha256
prepare_manifest

gpg --batch --no-tty --yes --default-key "$KEY_ID" --detach-sign --armor "$MANIFEST"

ok "Manifest signed: $SIGNATURE"

verify_signature

ok "Release package ready: $PACKAGE"
ok "Manifest updated and signed: $MANIFEST"
