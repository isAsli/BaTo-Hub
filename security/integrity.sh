#!/usr/bin/env bash
set -euo pipefail

ROOT="${INSTALL_DIR:-/opt/batohub}"
CONFIG_DIR="${CONFIG_DIR:-/etc/batohub}"
MANIFEST="${CONFIG_DIR}/integrity.sha256"
LOCK_FILE="${CONFIG_DIR}/integrity.lock"

verify_integrity() {
  if [ ! -f "$MANIFEST" ]; then
    err "Integrity manifest is missing: $MANIFEST"
    return 1
  fi
  if ! sha256sum -c "$MANIFEST" --quiet 2>/dev/null; then
    err "Integrity verification failed."
    return 1
  fi
  return 0
}

write_integrity() {
  local tmp fd
  need_root
  tmp=$(mktemp_file "integrity")
  : > "$tmp"
  find "$ROOT/core" "$ROOT/lib" "$ROOT/modules" "$ROOT/bin" \
    -type f \( -perm /111 -o -name '*.sh' \) 2>/dev/null \
    | sort \
    | while read -r f; do
        sha256sum "$f"
      done > "$tmp"

  chmod 600 "$tmp"
  chown root:root "$tmp"
  mv -f "$tmp" "$MANIFEST"
  log "Integrity manifest written: $MANIFEST"
}

verify_and_write_integrity() {
  local fd
  fd=$(lock_acquire "$LOCK_FILE")
  write_integrity
  verify_integrity
  lock_release "$fd"
}
