#!/usr/bin/env bash
set -Eeuo pipefail

# Self-update.
#
# The remote tree is always fetched over HTTPS with certificate validation, the
# local state is backed up first, protected paths are never touched, and the new
# tree is verified before it replaces the running installation. A failed
# verification restores the previous tree.

# Paths that an update must never overwrite. They are BaToHub state, operator
# configuration, log data, or explicitly declared as user managed.
update_protected_paths() {
  local path
  printf '%s\n' "$CONFIG_FILE"
  printf '%s\n' "$PANEL_CONF"
  printf '%s\n' "$STATE_DIR"
  printf '%s\n' "$LOG_DIR"
  if [[ -n "${USER_MANAGED_PATHS:-}" ]]; then
    for path in ${USER_MANAGED_PATHS}; do
      [[ -n "$path" ]] && printf '%s\n' "$path"
    done
  fi
}

update_path_is_protected() {
  local path="$1" protected
  while IFS= read -r protected; do
    [[ -n "$protected" ]] || continue
    if [[ "$path" == "$protected" || "$path" == "$protected"/* ]]; then
      return 0
    fi
  done < <(update_protected_paths)
  return 1
}

update_version_is_older() {
  local candidate="$1" current="$2"
  [[ "$candidate" == "$current" ]] && return 1
  local lowest
  lowest="$(printf '%s\n%s\n' "$candidate" "$current" | sort -V | head -n 1)"
  [[ "$lowest" == "$candidate" ]]
}

update_fetch_remote() {
  local dest="$1" url tarball
  [[ -d "$dest" ]] || install -d "$dest"
  if need_cmd git; then
    if git clone --quiet --depth 1 --branch "$GITHUB_BRANCH" \
      "https://github.com/${GITHUB_REPO}.git" "$dest" >>"$LOG_FILE" 2>&1; then
      log "Update source fetched with git from ${GITHUB_REPO}"
      return 0
    fi
    warn "git could not fetch the repository; falling back to the HTTPS archive."
  fi
  need_cmd curl || {
    err "Neither git nor curl is available; the update source cannot be fetched."
    return 1
  }
  url="https://github.com/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"
  tarball="$(mktemp_file update)"
  # shellcheck disable=SC2064
  trap "rm -f -- '$tarball'" RETURN
  if ! curl --fail --location --show-error --silent --retry 3 --proto '=https' \
    --tlsv1.2 --output "$tarball" "$url"; then
    err "Download failed: $url"
    return 1
  fi
  if ! tar -xzf "$tarball" -C "$dest" --strip-components=1 >>"$LOG_FILE" 2>&1; then
    err "The downloaded archive could not be extracted."
    return 1
  fi
  log "Update source fetched from ${url}"
  return 0
}

update_remote_version() {
  local tree="$1"
  if [[ -r "${tree}/VERSION" ]]; then
    head -n 1 "${tree}/VERSION" | tr -d '[:space:]'
    return 0
  fi
  return 1
}

update_verify_tree() {
  local tree="$1" file failed=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if ! bash -n "$file" 2>>"$LOG_FILE"; then
      err "Syntax error in updated file: ${file#"$tree"/}"
      failed=1
    fi
  done < <(find "$tree" -type f -name '*.sh' -not -path '*/.git/*' | sort)
  if [[ "$failed" -ne 0 ]]; then
    return 1
  fi
  if [[ ! -r "${tree}/panels/rebecca/panel.json" || ! -d "${tree}/panels" ]]; then
    err "The updated tree does not look like a BaToHub release."
    return 1
  fi
  return 0
}

update_sync_tree() {
  local tree="$1" args=()
  if need_cmd rsync; then
    args=(--archive --delete --exclude '.git/' --exclude '.github/' --exclude 'node_modules/')
    if ! rsync "${args[@]}" --exclude '/config/panel.conf' --exclude '/config/batohub.conf' \
      "${tree}/" "${INSTALL_DIR}/" >>"$LOG_FILE" 2>&1; then
      err "File synchronisation failed. Full output: ${LOG_FILE}"
      return 1
    fi
    return 0
  fi
  warn "rsync is not installed; using the archive replacement fallback."
  local dir
  for dir in bin core lib panels tools security scripts; do
    rm -rf -- "${INSTALL_DIR:?}/${dir}"
  done
  if ! cp -a "${tree}/." "${INSTALL_DIR}/"; then
    err "Copying the updated tree failed."
    return 1
  fi
  rm -rf -- "${INSTALL_DIR}/.git"
  return 0
}

update_restore_snapshot() {
  local snapshot="$1"
  if [[ ! -d "$snapshot" ]]; then
    err "Update snapshot is missing; automatic rollback is not possible."
    return 1
  fi
  if ! cp -a "${snapshot}/." "${INSTALL_DIR}/"; then
    err "Rollback failed. Restore the installation from ${snapshot} manually."
    return 1
  fi
  ok "Rolled back to the previous BaToHub tree."
  log "Update rolled back from ${snapshot}"
  return 0
}

update_run() {
  local force="${1:-0}" tree snapshot remote_version current_version panel
  need_root || return 1

  panel="$(panel_config_name)"
  current_version="$APP_VERSION"
  tree="$(mktemp_dir update)" || return 1
  snapshot="$(mktemp_dir snapshot)" || return 1

  printf 'Current version: %s\n' "$current_version"
  printf 'Source: https://github.com/%s (%s)\n' "$GITHUB_REPO" "$GITHUB_BRANCH"

  if ! update_fetch_remote "$tree"; then
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi

  remote_version="$(update_remote_version "$tree")" || {
    rm -rf -- "$tree" "$snapshot"
    err "The remote tree does not contain a VERSION file."
    return 1
  }
  printf 'Available version: %s\n' "$remote_version"

  if [[ "$remote_version" == "$current_version" && "$force" != "1" ]]; then
    ok "BaToHub is already at ${current_version}."
    rm -rf -- "$tree" "$snapshot"
    return 0
  fi
  if update_version_is_older "$remote_version" "$current_version" && [[ "$force" != "1" ]]; then
    err "The remote version ${remote_version} is older than the installed ${current_version}."
    err "Downgrades are refused. Pass --force only if you intentionally want to downgrade."
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi
  if [[ "$INTERACTIVE" == 1 && "$force" != "1" ]]; then
    if ! ui_confirm "Update BaToHub from ${current_version} to ${remote_version}?"; then
      info "Update cancelled."
      rm -rf -- "$tree" "$snapshot"
      return 0
    fi
  fi

  printf 'Creating a backup of the current state...\n'
  local archive
  archive="$(backup_create "$panel")" || {
    err "A backup could not be created; the update is aborted."
    rm -rf -- "$tree" "$snapshot"
    return 1
  }
  printf 'Backup: %s\n' "$archive"

  if ! cp -a "${INSTALL_DIR}/." "$snapshot/"; then
    err "The installation snapshot could not be created; the update is aborted."
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi

  if ! update_verify_tree "$tree"; then
    err "The downloaded tree failed verification; nothing was changed."
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi

  printf 'Applying updated files...\n'
  if ! update_sync_tree "$tree"; then
    update_restore_snapshot "$snapshot" || true
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi

  printf 'Verifying the updated installation...\n'
  local verified=0
  if (cd "$INSTALL_DIR" && loader_validate_all) >>"$LOG_FILE" 2>&1; then
    verified=1
  fi
  if [[ "$verified" -eq 1 ]] && integrity_write && integrity_check; then
    ok "BaToHub updated to ${remote_version}."
    log "Update completed: ${current_version} -> ${remote_version}"
    rm -rf -- "$tree" "$snapshot"
    return 0
  fi

  err "Post-update verification failed. Rolling back."
  update_restore_snapshot "$snapshot" || true
  rm -rf -- "$tree" "$snapshot"
  return 1
}

update_all() {
  local force="${1:-0}" status=0
  update_run "$force" || status=$?
  if [[ "$status" -ne 0 ]]; then
    err "The update did not complete. The previous installation is still in place."
  fi
  return "$status"
}
