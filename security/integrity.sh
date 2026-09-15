#!/usr/bin/env bash
set -Eeuo pipefail

# Integrity manifests.
#
# BaToHub records a SHA-256 manifest of every file it ships. The manifest is
# only a tamper detector: a root user can still modify the files on disk, and the
# check reports that instead of pretending the installation is immutable.

INTEGRITY_MANIFEST="${CONFIG_DIR}/integrity.sha256"
INTEGRITY_LOCK="${CONFIG_DIR}/integrity.lock"

integrity_targets() {
  # Grouped -o expressions; without the parentheses only the last -name would be
  # subject to -type f.
  find "$INSTALL_DIR" -type f \
    \( -name '*.sh' -o -name '*.json' -o -name 'VERSION' -o -name '*.html' \) \
    -not -path '*/.git/*' -print0 2>/dev/null | sort -z
}

integrity_write_unlocked() {
  local tmp
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  tmp="$(mktemp "${CONFIG_DIR}/.integrity.XXXXXX")"
  chmod 0600 "$tmp"
  if ! (cd "$INSTALL_DIR" && integrity_targets | xargs -0r sha256sum) >"$tmp"; then
    rm -f -- "$tmp"
    err "Integrity manifest generation failed."
    return 1
  fi
  if [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"
    err "Integrity manifest is empty; the installation directory looks wrong."
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$INTEGRITY_MANIFEST"
  chmod 0600 "$INTEGRITY_MANIFEST"
  chown root:root "$INTEGRITY_MANIFEST" 2>/dev/null || true
}

integrity_write() {
  need_root || return 1
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  exec 9>"$INTEGRITY_LOCK"
  flock -x 9
  set +e
  integrity_write_unlocked
  local status=$?
  set -e
  flock -u 9 2>/dev/null || true
  exec 9>&-
  if [[ "$status" -ne 0 ]]; then
    return "$status"
  fi
  log "Integrity manifest written: $INTEGRITY_MANIFEST"
  return 0
}

# A missing manifest is a hard failure: without it there is nothing to compare
# against, so the caller must not treat the installation as verified.
integrity_check() {
  if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
    err "Integrity manifest is missing: $INTEGRITY_MANIFEST"
    err "Run the BaToHub installer again, or run: BaToHub --check --rebuild"
    return 1
  fi
  local output status
  set +e
  output="$(cd "$INSTALL_DIR" && sha256sum -c "$INTEGRITY_MANIFEST" --quiet 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    err "Integrity check failed; the following files differ from the recorded manifest:"
    printf '%s\n' "$output" | sed 's/^/  /' >&2
    log "INTEGRITY_FAIL ${output//$'\n'/ }"
    return 1
  fi
  return 0
}

integrity_check_quiet() {
  [[ -f "$INTEGRITY_MANIFEST" ]] || return 1
  (cd "$INSTALL_DIR" && sha256sum -c "$INTEGRITY_MANIFEST" --quiet >/dev/null 2>&1)
}

integrity_status_line() {
  if [[ ! -f "$INTEGRITY_MANIFEST" ]]; then
    printf '%s\n' 'integrity: manifest missing'
    return 1
  fi
  if integrity_check_quiet; then
    printf '%s\n' 'integrity: verified'
    return 0
  fi
  printf '%s\n' 'integrity: mismatched files detected'
  return 1
}

integrity_apply_before_run() {
  # Called by the entry point. A mismatch is reported and logged, but the
  # operator keeps control: BaToHub is a management tool, not a boot loader.
  if ! integrity_check; then
    warn "The installation does not match its integrity manifest. Review the report above."
    warn "Log entry written to $LOG_FILE"
    return 1
  fi
  return 0
}

integrity_rebuild_and_verify() {
  integrity_write || return 1
  integrity_check || return 1
  ok "Integrity manifest rebuilt and verified."
}
