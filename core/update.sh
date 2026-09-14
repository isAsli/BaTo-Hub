#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

update_all() {
  local tmp latest url sha z github_json ghver ghurl signature_tmp rollback_dir rc
  header

  info 'Checking central update server...'

  tmp=$(mktemp_file "manifest")
  signature_tmp=$(mktemp_file "manifest_sig")

  if ! curl -fsS --max-time 15 --cacert /etc/ssl/certs/ca-certificates.crt \
    "$UPDATE_MANIFEST" -o "$tmp" 2>>"$LOG_FILE"; then
    err 'Central update manifest unavailable.'
    rm -f "$tmp" "$signature_tmp"
    pause
    return
  fi

  if ! curl -fsS --max-time 15 --cacert /etc/ssl/certs/ca-certificates.crt \
    "$MANIFEST_SIGNATURE" -o "$signature_tmp" 2>>"$LOG_FILE"; then
    info 'Manifest signature file unavailable; update check skipped for safety.'
    rm -f "$tmp" "$signature_tmp"
    pause
    return
  fi

  if ! gpg --batch --no-tty --verify "$signature_tmp" "$tmp" 2>>"$LOG_FILE"; then
    err 'Manifest signature verification failed.'
    rm -f "$tmp" "$signature_tmp"
    pause
    return
  fi

  latest=$(json_get "$tmp" version)
  url=$(json_get "$tmp" package)
  sha=$(json_get "$tmp" sha256)

  if [ -z "$latest" ] || [ -z "$url" ]; then
    err 'Update manifest is missing required fields.'
    rm -f "$tmp" "$signature_tmp"
    pause
    return
  fi

  if [ "$latest" = "$APP_VERSION" ]; then
    ok "BaToHub $APP_VERSION is current."
    rm -f "$tmp" "$signature_tmp"
    pause
    return
  fi

  if [ -n "$sha" ]; then
    ok "New BaToHub version: $latest"
  else
    err 'Update manifest is missing the package SHA-256.'
    rm -f "$tmp" "$signature_tmp"
    pause
    return
  fi

  # Download package into a unique temp file.
  z=$(mktemp_file "update")
  if ! curl -fL --max-time 120 --cacert /etc/ssl/certs/ca-certificates.crt \
    "$url" -o "$z" 2>>"$LOG_FILE"; then
    err 'Central update package unavailable.'
    rm -f "$tmp" "$signature_tmp" "$z"
    pause
    return
  fi

  local computed_sha
  computed_sha=$(sha256sum "$z" | awk '{print $1}')
  if [ "$computed_sha" != "$sha" ]; then
    err 'Update checksum mismatch.'
    rm -f "$tmp" "$signature_tmp" "$z"
    pause
    return
  fi

  # Verify the ZIP contains the expected VERSION file before replacing anything.
  if ! unzip -l "$z" 2>/dev/null | grep -qE '^[^/]*/VERSION$'; then
    err 'Invalid update package.'
    rm -f "$tmp" "$signature_tmp" "$z"
    pause
    return
  fi

  # Backup current installation.
  rollback_dir="/opt/batohub.backup.$(date +%Y%m%d%H%M%S)"
  if [ -d "${INSTALL_DIR:-/opt/batohub}" ]; then
    cp -a "${INSTALL_DIR:-/opt/batohub}" "$rollback_dir"
  else
    err 'Existing BaToHub installation not found; cannot update safely.'
    rm -f "$tmp" "$signature_tmp" "$z"
    pause
    return
  fi

  local new_root
  new_root=$(mktemp_dir "update_root")
  if ! unzip -q -o "$z" -d "$new_root" 2>>"$LOG_FILE"; then
    err 'Failed to extract update package.'
    rm -rf "$new_root"
    rm -f "$tmp" "$signature_tmp" "$z"
    pause
    return
  fi

  if [ ! -f "${new_root}/VERSION" ]; then
    err 'Invalid update package.'
    rm -rf "$new_root"
    rm -f "$tmp" "$signature_tmp" "$z"
    pause
    return
  fi

  # Apply update.
  rm -rf "${INSTALL_DIR:-/opt/batohub}"
  mv "$new_root" "${INSTALL_DIR:-/opt/batohub}"

  # Restore executable permissions safely.
  find "${INSTALL_DIR:-/opt/batohub}/bin" "${INSTALL_DIR:-/opt/batohub}/core" \
    "${INSTALL_DIR:-/opt/batohub}/lib" "${INSTALL_DIR:-/opt/batohub}/security" \
    "${INSTALL_DIR:-/opt/batohub}/modules/rebecca/ssl" \
    "${INSTALL_DIR:-/opt/batohub}/modules/rebecca/templates" \
    -type f -name '*.sh' -exec chmod +x {} + || true

  chown -R root:root "${INSTALL_DIR:-/opt/batohub}" 2>/dev/null || true
  chmod 600 "${CONFIG_DIR}/batohub.conf" 2>/dev/null || true

  # Rebuild integrity manifest.
  . "${INSTALL_DIR:-/opt/batohub}/security/integrity.sh"
  write_integrity

  rm -f "$tmp" "$signature_tmp" "$z"

  ok "BaToHub updated to $latest"

  # If anything after this point fails, attempt rollback.
  if ! verify_integrity; then
    err 'Post-update integrity check failed; attempting rollback.'
    if [ -d "$rollback_dir" ]; then
      rm -rf "${INSTALL_DIR:-/opt/batohub}"
      mv "$rollback_dir" "${INSTALL_DIR:-/opt/batohub}"
      ok 'Rollback completed.'
    else
      err 'Rollback backup not found; manual recovery may be required.'
    fi
    pause
    return
  fi

  ok 'Update verified.'
  pause
}
