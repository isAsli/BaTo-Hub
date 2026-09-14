#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

BACKUP_DIR="${BACKUP_DIR:-${STATE_DIR}/backups}"
BACKUP_KEEP="${BACKUP_KEEP:-5}"

init_backup_dir() {
  install -d -m 750 "$BACKUP_DIR" 2>/dev/null || true
  chmod 750 "$BACKUP_DIR" 2>/dev/null || true
  chown root:root "$BACKUP_DIR" 2>/dev/null || true
}

list_backups() {
  init_backup_dir
  if [ ! -d "$BACKUP_DIR" ]; then
    err "Backup directory not found."
    return 1
  fi
  local f
  for f in "$BACKUP_DIR"/*.tar.gz; do
    if [ -f "$f" ]; then
      local base checksum size date
      base=$(basename "$f")
      checksum="${f}.sha256"
      size=$(stat -c %s "$f" 2>/dev/null || echo '0')
      date=$(date -r "$f" '+%F %T' 2>/dev/null || echo 'unknown')
      printf '%s\n' "$base  size=${size}  date=${date}  checksum=${checksum}"
    fi
  done
}

create_backup() {
  local panel="$1"
  local backup_name backup_file checksum_file metadata_file
  backup_name="$(date +%Y%m%d%H%M%S)"
  backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
  checksum_file="${backup_file}.sha256"
  metadata_file="${BACKUP_DIR}/${backup_name}.meta"

  init_backup_dir

  local include_paths
  include_paths="${CONFIG_DIR}
${STATE_DIR}
${LOG_DIR}"
  local panel_dir
  panel_dir=$(panel_detect_path "$panel")
  if [ -n "$panel_dir" ]; then
    include_paths="${include_paths}
${panel_dir}"
  fi

  if [ ! -d "$BACKUP_DIR" ]; then
    err "Backup directory not created."
    return 1
  fi

  if tar -czf "$backup_file" --preserve-permissions -C / \
    etc/batohub \
    var/lib/batohub \
    var/log/batohub \
    "$(panel_detect_path "$panel" 2>/dev/null | sed "s|^/||")" 2>/dev/null; then
    :
  else
    err "Backup creation failed."
    rm -f "$backup_file"
    return 1
  fi

  chmod 600 "$backup_file" 2>/dev/null || true
  chown root:root "$backup_file" 2>/dev/null || true

  sha256sum "$backup_file" > "$checksum_file"
  chmod 600 "$checksum_file" 2>/dev/null || true
  chown root:root "$checksum_file" 2>/dev/null || true

  local metadata
  metadata=$(printf '%s\n' \
    "version=${APP_VERSION}" \
    "panel=$(panel_display_name "$panel")" \
    "panel_version=$(panel_version "$panel")" \
    "timestamp=$(date '+%F %T')" \
    "panel_path=$(panel_detect_path "$panel" 2>/dev/null || true)")
  printf '%s\n' "$metadata" > "$metadata_file"
  chmod 600 "$metadata_file" 2>/dev/null || true
  chown root:root "$metadata_file" 2>/dev/null || true

  ok "Backup created: $backup_file"
  info "Checksum: $checksum_file"
  info "Metadata: $metadata_file"
  cleanup_old_backups
  return 0
}

cleanup_old_backups() {
  init_backup_dir
  local count=0
  local files
  files=$(find "$BACKUP_DIR" -maxdepth 1 -name '*.tar.gz' -type f | sort)
  if [ -z "$files" ]; then
    return 0
  fi
  local keep="$BACKUP_KEEP"
  local removed=0
  while IFS= read -r f; do
    count=$((count + 1))
    if [ "$count" -gt "$keep" ]; then
      rm -f "$f" "${f}.sha256" "${f}.meta" 2>/dev/null || true
      removed=$((removed + 1))
    fi
  done <<< "$files"
  if [ "$removed" -gt 0 ]; then
    info "Removed $removed old backup(s)."
  fi
}

verify_backup_checksum() {
  local backup_file="$1"
  local checksum_file="${backup_file}.sha256"
  if [ ! -f "$checksum_file" ]; then
    err "Checksum file not found for $backup_file"
    return 1
  fi
  if sha256sum -c "$checksum_file" --status 2>/dev/null; then
    ok "Checksum verified for $backup_file"
    return 0
  else
    err "Checksum mismatch for $backup_file"
    return 1
  fi
}

restore_backup() {
  local backup_file="$1"
  local panel="$2"
  local tmp_dir
  tmp_dir=$(mktemp_dir "restore")

  if ! verify_backup_checksum "$backup_file"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  # Safety backup of current state.
  create_backup "$panel"

  if ! tar -xzf "$backup_file" -C "$tmp_dir" 2>/dev/null; then
    err "Restore extraction failed."
    rm -rf "$tmp_dir"
    return 1
  fi

  # Transactional move into place.
  if [ -d "$tmp_dir/etc/batohub" ]; then
    rm -rf "${CONFIG_DIR}"
    mv "$tmp_dir/etc/batohub" "${CONFIG_DIR}"
    chmod 750 "${CONFIG_DIR}" 2>/dev/null || true
    chown root:root "${CONFIG_DIR}" 2>/dev/null || true
    chmod 600 "${CONFIG_DIR}/panel.conf" 2>/dev/null || true
    chmod 600 "${CONFIG_DIR}/batohub.conf" 2>/dev/null || true
  fi

  if [ -d "$tmp_dir/var/lib/batohub" ]; then
    rm -rf "${STATE_DIR}"
    mv "$tmp_dir/var/lib/batohub" "${STATE_DIR}"
    chmod 750 "${STATE_DIR}" 2>/dev/null || true
    chown root:root "${STATE_DIR}" 2>/dev/null || true
  fi

  if [ -d "$tmp_dir/var/log/batohub" ]; then
    rm -rf "${LOG_DIR}"
    mv "$tmp_dir/var/log/batohub" "${LOG_DIR}"
    chmod 750 "${LOG_DIR}" 2>/dev/null || true
    chown root:root "${LOG_DIR}" 2>/dev/null || true
  fi

  rm -rf "$tmp_dir"
  ok "Restore completed from $backup_file"
  return 0
}

import_backup() {
  local external_file="$1"
  local panel="$2"
  local checksum_file="$external_file.sha256"
  local tmp_dir
  tmp_dir=$(mktemp_dir "import")

  if [ ! -f "$external_file" ]; then
    err "External backup file not found: $external_file"
    rm -rf "$tmp_dir"
    return 1
  fi

  if [ -f "$checksum_file" ]; then
    if ! sha256sum -c "$checksum_file" --status 2>/dev/null; then
      err "Checksum mismatch for external backup."
      rm -rf "$tmp_dir"
      return 1
    fi
    ok "External checksum verified."
  else
    warn "No checksum file found; import continues without verification."
  fi

  create_backup "$panel"

  if ! tar -xzf "$external_file" -C "$tmp_dir" 2>/dev/null; then
    err "Import extraction failed."
    rm -rf "$tmp_dir"
    return 1
  fi

  if [ -d "$tmp_dir/etc/batohub" ]; then
    rm -rf "${CONFIG_DIR}"
    mv "$tmp_dir/etc/batohub" "${CONFIG_DIR}"
    chmod 750 "${CONFIG_DIR}" 2>/dev/null || true
    chown root:root "${CONFIG_DIR}" 2>/dev/null || true
    chmod 600 "${CONFIG_DIR}/panel.conf" 2>/dev/null || true
    chmod 600 "${CONFIG_DIR}/batohub.conf" 2>/dev/null || true
  fi

  if [ -d "$tmp_dir/var/lib/batohub" ]; then
    rm -rf "${STATE_DIR}"
    mv "$tmp_dir/var/lib/batohub" "${STATE_DIR}"
    chmod 750 "${STATE_DIR}" 2>/dev/null || true
    chown root:root "${STATE_DIR}" 2>/dev/null || true
  fi

  if [ -d "$tmp_dir/var/log/batohub" ]; then
    rm -rf "${LOG_DIR}"
    mv "$tmp_dir/var/log/batohub" "${LOG_DIR}"
    chmod 750 "${LOG_DIR}" 2>/dev/null || true
    chown root:root "${LOG_DIR}" 2>/dev/null || true
  fi

  rm -rf "$tmp_dir"
  ok "Import completed from $external_file"
  return 0
}

backup_menu() {
  local panel="$1"
  while :; do
    header
    printf '%s\n' "Backup and restore"
    printf '%s\n' "----------------------------------------"
    printf '%s\n' "1) Create backup"
    printf '%s\n' "2) List backups"
    printf '%s\n' "0) Back"
    read -r -p "Selection: " c
    case "$c" in
      1)
        header
        if ! confirm "Create a backup of current BaToHub state and panel data?"; then
          pause
          continue
        fi
        create_backup "$panel"
        pause
        ;;
      2)
        header
        list_backups
        pause
        ;;
      0) return;;
    esac
  done
}

restore_menu() {
  local panel="$1"
  while :; do
    header
    printf '%s\n' "Restore"
    printf '%s\n' "----------------------------------------"
    printf '%s\n' "1) List backups and restore"
    printf '%s\n' "0) Back"
    read -r -p "Selection: " c
    case "$c" in
      1)
        header
        local backup
        backup=$(list_backups | sed -n '1p' | awk '{print $1}')
        if [ -z "$backup" ]; then
          err "No backups found."
          pause
          continue
        fi
        local backup_path="${BACKUP_DIR}/${backup}"
        if ! confirm "Restore from $backup_path?"; then
          pause
          continue
        fi
        restore_backup "$backup_path" "$panel"
        pause
        ;;
      0) return;;
    esac
  done
}

import_menu() {
  local panel="$1"
  while :; do
    header
    printf '%s\n' "Import backup"
    printf '%s\n' "----------------------------------------"
    printf '%s\n' "1) Import external backup file"
    printf '%s\n' "0) Back"
    read -r -p "Selection: " c
    case "$c" in
      1)
        header
        local external
        read -r -p "Path to backup file: " external
        external=$(printf '%s' "$external" | sed 's/[[:space:]]//g')
        if [ -z "$external" ]; then
          err "No path provided."
          pause
          continue
        fi
        if ! confirm "Import $external?"; then
          pause
          continue
        fi
        import_backup "$external" "$panel"
        pause
        ;;
      0) return;;
    esac
  done
}
