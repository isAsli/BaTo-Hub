#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

PACKAGE="BaToHub-0.0.1.zip"
MANIFEST="manifest.json"
SIGNATURE="$MANIFEST.sig"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root."
    exit 1
  fi
}

prepare_manifest() {
  local tmp
  tmp=$(mktemp_file "manifest")
  python3 - "$MANIFEST" "$PACKAGE" "$SHA256" <<'PY'
import json
import sys
import hashlib

manifest_path = sys.argv[1]
package_name = sys.argv[2]
sha256 = sys.argv[3]

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

manifest["sha256"] = sha256

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

# Build a release ZIP from the repo tree.
zip -r "$PACKAGE" . -x "*.git*" -x "__pycache__/*" -x "*.swp" -x ".DS_Store"

compute_sha256
prepare_manifest

# Sign the manifest.
gpg --batch --no-tty --yes --default-key "$KEY_ID" --detach-sign --armor "$MANIFEST"

ok "Manifest signed: $SIGNATURE"

verify_signature

ok "Release package ready: $PACKAGE"
ok "Manifest updated and signed: $MANIFEST"
