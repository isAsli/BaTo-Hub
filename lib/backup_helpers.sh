#!/usr/bin/env bash
set -Eeuo pipefail

# Backup, restore and import primitives.
#
# A backup is a gzip tarball produced from the filesystem root using relative
# member names, plus a SHA-256 sidecar and a metadata file that lists every path
# the archive may contain. Restore refuses any member that is not declared in
# that metadata, verifies the checksum first, and takes a safety backup of the
# current state before it writes anything.

BACKUP_META_NAME="BaToHub-backup.meta"

backup_meta_path() { printf '%s\n' "$BACKUP_META_NAME"; }

backup_state_paths() {
  printf '%s\n' "$CONFIG_DIR"
  printf '%s\n' "$STATE_DIR"
  printf '%s\n' "$LOG_DIR"
}

backup_paths_for_panel() {
  local panel="${1:-}" path
  backup_state_paths
  while IFS= read -r path; do
    case "$path" in
    "$BACKUP_DIR" | "$BACKUP_DIR"/*) continue ;;
    esac
    [[ -e "$path" || -L "$path" ]] && printf '%s\n' "$path"
  done < <(panel_declared_paths "$panel")
}

backup_create() {
  local panel="${1:-}" stamp archive checksum meta_dir meta_tmp list_tmp path panel_version
  local -a members
  need_root || return 1
  install -d -m 0750 -o root -g root "$BACKUP_DIR"
  stamp="$(current_timestamp)"
  archive="${BACKUP_DIR}/${stamp}.tar.gz"
  checksum="${archive}.sha256"
  meta_dir="$(mktemp_dir meta)"
  meta_tmp="${meta_dir}/${BACKUP_META_NAME}"
  list_tmp="$(mktemp_file list)"
  panel_version="unknown"
  if [[ -n "$panel" ]]; then
    panel_version="$(panel_version_of "$panel")"
  fi

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    printf '%s\n' "${path#/}" >>"$list_tmp"
  done < <(backup_paths_for_panel "$panel" | sort -u)

  if [[ ! -s "$list_tmp" ]]; then
    rm -rf -- "$meta_dir"
    rm -f -- "$list_tmp"
    err "There is nothing to back up on this server."
    return 1
  fi

  {
    printf 'format=1\n'
    printf 'batohub_version=%s\n' "$APP_VERSION"
    printf 'panel=%s\n' "${panel:-none}"
    printf 'panel_version=%s\n' "${panel_version:-unknown}"
    printf 'timestamp=%s\n' "$stamp"
    printf 'paths=%s\n' "$(tr '\n' ',' <"$list_tmp")"
  } >"$meta_tmp"
  chmod 0600 "$meta_tmp"

  # Member names are always relative to / so no absolute or parent path can be
  # stored, and the metadata file is appended from its own temporary directory.
  mapfile -t members <"$list_tmp"
  if ! tar --create --gzip --file "$archive" --preserve-permissions \
    --exclude="$(printf '%s' "${BACKUP_DIR#/}")" \
    -C / "${members[@]}" \
    -C "$meta_dir" "$BACKUP_META_NAME" >>"$LOG_FILE" 2>&1; then
    rm -f -- "$archive"
    rm -rf -- "$meta_dir" "$list_tmp"
    err "Backup creation failed. Full output: ${LOG_FILE}"
    return 1
  fi

  if ! sha256sum "$archive" >"$checksum" 2>>"$LOG_FILE"; then
    rm -f -- "$archive" "$checksum"
    rm -rf -- "$meta_dir" "$list_tmp"
    err "Checksum generation failed."
    return 1
  fi
  rm -rf -- "$meta_dir"
  rm -f -- "$list_tmp"
  chmod 0600 "$archive" "$checksum"
  chown root:root "$archive" "$checksum" 2>/dev/null || true
  backup_rotate
  log "Backup created: $archive"
  printf '%s\n' "$archive"
}

backup_rotate() {
  local keep="${BACKUP_KEEP:-5}" count=0 file
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    count=$((count + 1))
    if ((count > keep)); then
      rm -f -- "$file" "${file}.sha256"
      log "Backup rotated out: $file"
    fi
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | cut -d' ' -f2-)
}

backup_list() {
  local file
  if [[ ! -d "$BACKUP_DIR" ]]; then
    warn "No backup directory exists yet: $BACKUP_DIR"
    return 1
  fi
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    printf '%s  %s bytes  %s\n' \
      "$file" \
      "$(stat -c '%s' "$file" 2>/dev/null || printf '?')" \
      "$(date -r "$file" '+%F %T' 2>/dev/null || printf 'unknown')"
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' 2>/dev/null | sort)
}

backup_verify() {
  local archive="$1" expected actual
  [[ -f "$archive" ]] || {
    err "Backup archive not found: $archive"
    return 1
  }
  [[ -f "${archive}.sha256" ]] || {
    err "Checksum file not found: ${archive}.sha256"
    return 1
  }
  expected="$(awk '{print $1}' "${archive}.sha256")"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    err "Checksum mismatch for ${archive}."
    err "Expected: ${expected}"
    err "Actual:   ${actual}"
    return 1
  fi
  ok "Checksum verified."
}

backup_read_meta() {
  local archive="$1"
  tar -xzOf "$archive" "$BACKUP_META_NAME" 2>/dev/null
}

backup_meta_field() {
  local archive="$1" key="$2"
  backup_read_meta "$archive" | grep -E "^${key}=" | tail -n 1 | cut -d= -f2- || true
}

backup_declared_paths() {
  local archive="$1" list
  list="$(backup_meta_field "$archive" paths)"
  [[ -n "$list" ]] || return 1
  printf '%s\n' "$list" | tr ',' '\n'
}

# Restore destinations follow the configured roots, so an installation that uses
# non-default directories restores into those directories instead of the
# packaged defaults. Paths outside the BaToHub roots stay where they are.
backup_map_destination() {
  local relative="$1"
  case "$relative" in
  etc/batohub) printf '%s\n' "$CONFIG_DIR" ;;
  etc/batohub/*) printf '%s/%s\n' "$CONFIG_DIR" "${relative#etc/batohub/}" ;;
  var/lib/batohub) printf '%s\n' "$STATE_DIR" ;;
  var/lib/batohub/*) printf '%s/%s\n' "$STATE_DIR" "${relative#var/lib/batohub/}" ;;
  var/log/batohub) printf '%s\n' "$LOG_DIR" ;;
  var/log/batohub/*) printf '%s/%s\n' "$LOG_DIR" "${relative#var/log/batohub/}" ;;
  *) printf '/%s\n' "$relative" ;;
  esac
}

# Destination roots a restore may ever write to. Members outside these
# prefixes are rejected even if a metadata file claims them, so a crafted
# archive cannot point the restore at /etc, /root or any other location.
backup_allowed_prefixes() {
  printf '%s\n' "${CONFIG_DIR#/}"
  printf '%s\n' "${STATE_DIR#/}"
  printf '%s\n' "${LOG_DIR#/}"
}

# A member is safe when it is relative, carries no parent traversal, and sits
# below one of the destination roots.
backup_member_is_allowed() {
  local member="$1" prefix
  [[ "$member" == /* ]] && return 1
  [[ "$member" == *..* ]] && return 1
  [[ -z "$member" ]] && return 1
  while IFS= read -r prefix; do
    [[ -n "$prefix" ]] || continue
    if [[ "$member" == "$prefix" || "$member" == "$prefix"/* ]]; then
      return 0
    fi
  done < <(backup_allowed_prefixes)
  return 1
}

# The metadata file is part of the archive input, so it is validated before any
# member check trusts it. Only the known keys with sane values are accepted.
backup_meta_is_valid() {
  local archive="$1" meta line key value paths=""
  meta="$(backup_read_meta "$archive")" || return 1
  [[ -n "$meta" ]] || return 1
  local saw_format=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
    *=*) ;;
    *) return 1 ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
    format)
      [[ "$value" == "1" ]] || return 1
      saw_format=1
      ;;
    batohub_version | panel | panel_version | timestamp)
      [[ "$value" =~ ^[A-Za-z0-9._:+-]*$ ]] || return 1
      ;;
    paths)
      # Every declared path must itself be relative, free of traversal, and
      # below a destination root. The value is a comma separated list.
      local entry
      while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        backup_member_is_allowed "$entry" || return 1
      done < <(printf '%s' "$value" | tr ',' '\n')
      [[ -n "$value" ]] || return 1
      paths="$value"
      ;;
    *) return 1 ;;
    esac
  done <<<"$meta"
  [[ "$saw_format" -eq 1 && -n "$paths" ]]
}

backup_validate_archive() {
  local archive="$1" member declared_paths candidate matched target link_target
  backup_meta_is_valid "$archive" || {
    err "Backup metadata is missing, malformed, or declares paths outside the BaToHub destination roots; refusing to restore."
    return 1
  }
  declared_paths="$(backup_declared_paths "$archive")"
  # Pass 1: member names must be relative, free of parent traversal, below a
  # destination root, and declared in the metadata.
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    # Directory members carry a trailing slash; the metadata stores plain paths.
    member="${member%/}"
    [[ -n "$member" ]] || continue
    if [[ "$member" == "$BACKUP_META_NAME" ]]; then
      continue
    fi
    if ! backup_member_is_allowed "$member"; then
      err "Backup contains an unsafe member path: $member"
      return 1
    fi
    matched=0
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      if [[ "$member" == "$candidate" || "$member" == "$candidate"/* ]]; then
        matched=1
        break
      fi
    done <<<"$declared_paths"
    if [[ "$matched" -ne 1 ]]; then
      err "Backup contains a path that is not declared in its metadata: $member"
      return 1
    fi
  done < <(tar -tzf "$archive")
  # Pass 2: symlink members are resolved from the extraction listing; a link
  # that points outside the destination roots would redirect the restore. The
  # listing is parsed positionally so a target is never confused with a path.
  while IFS='|' read -r link_path link_target; do
    [[ -n "${link_path:-}" ]] || continue
    link_path="${link_path%/}"
    [[ "$(basename "$link_path")" == "$BACKUP_META_NAME" ]] && continue
    if ! backup_member_is_allowed "$link_path"; then
      err "Backup contains a symlink outside the BaToHub destination roots: $link_path"
      return 1
    fi
    case "$link_target" in
    /* | *..*)
      err "Backup contains a symlink with an unsafe target: $link_path -> $link_target"
      return 1
      ;;
    esac
  done < <(tar -tvzf "$archive" 2>/dev/null |
    sed -n 's/^[^ ][^ ]* [^ ][^ ]* [^ ][^ ]* [^ ][^ ]* [^ ][^ ]* \(.*\) -> \(.*\)$/\1|\2/p')
  ok "Backup contents validated against its metadata and the destination roots."
}

backup_restore() {
  local archive="$1" panel="${2:-}" declared extract safety relative
  need_root || return 1
  [[ -f "$archive" ]] || {
    err "Backup archive not found: $archive"
    return 1
  }
  backup_verify "$archive" || return 1
  backup_validate_archive "$archive" || return 1

  safety="$(backup_create "$panel")" || {
    err "A safety backup of the current state could not be created; restore aborted."
    return 1
  }
  printf 'Safety backup: %s\n' "$safety"

  extract="$(mktemp_dir restore)"
  if ! tar -xzf "$archive" -C "$extract" >>"$LOG_FILE" 2>&1; then
    rm -rf -- "$extract"
    err "Extraction failed."
    return 1
  fi

  local destination
  while IFS= read -r declared; do
    [[ -n "$declared" ]] || continue
    relative="${declared#/}"
    [[ -e "${extract}/${relative}" ]] || continue
    destination="$(backup_map_destination "$relative")"
    if [[ -d "${extract}/${relative}" ]]; then
      install -d -m 0750 -o root -g root "$destination"
      cp -a "${extract}/${relative}/." "${destination}/"
    else
      install -d -m 0750 -o root -g root "$(dirname "$destination")"
      cp -a "${extract}/${relative}" "$destination"
    fi
  done < <(backup_declared_paths "$archive")

  rm -rf -- "$extract"
  harden_dir "$CONFIG_DIR" 0750
  harden_dir "$STATE_DIR" 0750
  harden_dir "$LOG_DIR" 0750
  harden_file "$PANEL_CONF" 0600
  harden_file "$CONFIG_FILE" 0600
  log "Restore completed from $archive"
  ok "Restore completed from ${archive}"
}

backup_import() {
  local source="$1" target panel="${2:-}"
  need_root || return 1
  [[ -f "$source" ]] || {
    err "Import source not found: $source"
    return 1
  }
  install -d -m 0750 -o root -g root "$BACKUP_DIR"
  target="${BACKUP_DIR}/$(basename "$source")"
  if [[ -e "$target" ]]; then
    err "A backup with this name already exists: $target"
    err "Rename the file or remove the existing backup first."
    return 1
  fi
  cp -a -- "$source" "$target"
  harden_file "$target" 0600
  if [[ -f "${source}.sha256" ]]; then
    cp -a -- "${source}.sha256" "${target}.sha256"
    harden_file "${target}.sha256" 0600
  else
    warn "No checksum file was provided with the import; a checksum will be generated locally."
    sha256sum "$target" >"${target}.sha256"
    harden_file "${target}.sha256" 0600
  fi
  backup_verify "$target" || return 1
  backup_validate_archive "$target" || return 1
  ok "Backup imported: $target"
  printf '%s\n' "$target"
  if [[ -n "$panel" ]]; then
    backup_restore "$target" "$panel"
  fi
}
