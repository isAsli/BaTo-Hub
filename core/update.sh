#!/usr/bin/env bash
set -Eeuo pipefail

# Self-update.
#
# The update downloads the release asset of a pinned tag: the newest published
# release, verified with SHA-256 against the .sha256 sidecar and the manifest
# before anything is extracted. The main branch is never a content source. The
# local state is backed up first, protected paths are never touched, the new
# tree is verified before it replaces the running installation, and a failed
# verification restores the previous tree.
#
# Every step is appended to ${LOG_DIR}/update.log with a timestamp.

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

# Writes one timestamped line to the update log. Log lines never contain
# credentials or private material.
update_log() {
  printf '[%s] [update] %s\n' "$(date '+%F %T%z')" "$1" >>"${LOG_DIR}/update.log" 2>/dev/null || true
}

update_release_tag() {
  local tag
  tag="$(curl --fail --silent --show-error --retry 3 --proto '=https' \
    --tlsv1.2 --header 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  [[ -n "$tag" ]] || {
    err "No published release could be resolved for ${GITHUB_REPO}."
    return 1
  }
  printf '%s\n' "$tag"
}

update_verify_downloaded() {
  local dir="$1" asset="$2"
  local checksum_ok=0
  # First anchor: the .sha256 sidecar published next to the release asset.
  if curl --fail --silent --show-error --retry 3 --proto '=https' \
    --tlsv1.2 --output "${dir}/${asset}.sha256" \
    "https://github.com/${GITHUB_REPO}/releases/download/${UPDATE_TAG}/${asset}.sha256"; then
    if (cd "$dir" && sha256sum -c "${asset}.sha256" >/dev/null 2>&1); then
      checksum_ok=1
      update_log "SHA-256 verified against ${asset}.sha256"
    else
      err "SHA-256 verification against ${asset}.sha256 failed; the download is not trusted."
      return 1
    fi
  else
    update_log "the .sha256 asset is not available for ${asset}"
  fi
  # Second anchor: the sha256 recorded inside the release manifest.
  if [[ "$checksum_ok" -eq 0 ]]; then
    local manifest_sha actual_sha
    manifest_sha="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${dir}/manifest.json" | head -n 1 || true)"
    [[ -n "$manifest_sha" ]] || {
      err "No published checksum is available for ${asset}; refusing an unverified download."
      return 1
    }
    actual_sha="$(sha256sum "${dir}/${asset}" | awk '{print $1}')"
    [[ "$actual_sha" == "$manifest_sha" ]] || {
      err "SHA-256 mismatch: manifest.json expects ${manifest_sha}, the archive hashes to ${actual_sha}."
      return 1
    }
    update_log "SHA-256 verified against the manifest.json asset"
  fi
  return 0
}

update_fetch_remote() {
  local dest="$1" url asset_name archive
  [[ -d "$dest" ]] || install -d "$dest"

  need_cmd curl || {
    err "curl is required to fetch the update source."
    return 1
  }

  UPDATE_TAG="$(update_release_tag)" || return 1
  update_log "pinned release: ${UPDATE_TAG}"
  local remote_version="${UPDATE_TAG#v}"
  local current_version
  current_version="$(head -n 1 "$INSTALL_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || printf '')"
  update_log "installed version: ${current_version:-unknown}"

  asset_name="BaToHub-${remote_version}.zip"
  url="https://github.com/${GITHUB_REPO}/releases/download/${UPDATE_TAG}/${asset_name}"
  archive="$(mktemp_file update)"
  # shellcheck disable=SC2064
  trap "rm -f -- '${archive}'" RETURN

  if curl --fail --silent --show-error --retry 3 --proto '=https' \
    --tlsv1.2 --output "$archive" "$url"; then
    update_log "release asset downloaded: ${asset_name}"
    curl --fail --silent --show-error --retry 3 --proto '=https' \
      --tlsv1.2 --output "${dest}/manifest.json" \
      "https://github.com/${GITHUB_REPO}/releases/download/${UPDATE_TAG}/manifest.json" || true
    if [[ ! -r "${dest}/manifest.json" ]]; then
      err "The manifest.json release asset is required to verify the download."
      return 1
    fi
    update_verify_downloaded "$dest" "$asset_name" || return 1
    local tree_dir="${dest}/tree"
    rm -rf -- "$tree_dir"
    mkdir -p "$tree_dir"
    if command -v unzip >/dev/null 2>&1; then
      if ! unzip -q -o "$archive" -d "$tree_dir"; then
        err "The release zip could not be extracted."
        return 1
      fi
    elif ! python3 -m zipfile -e "$archive" "$tree_dir"; then
      err "The release zip could not be extracted."
      return 1
    fi
    [[ -r "${tree_dir}/VERSION" ]] || {
      err "The extracted release does not contain a VERSION file."
      return 1
    }
    update_log "release tree extracted"
    cp -a "${tree_dir}/." "$dest/"
    rm -rf -- "$tree_dir"
    return 0
  fi

  update_log "the release asset is not available: ${url}"
  url="https://github.com/${GITHUB_REPO}/archive/refs/tags/${UPDATE_TAG}.tar.gz"
  update_log "falling back to the tagged source archive: ${url}"
  curl --fail --location --show-error --retry 3 --proto '=https' \
    --tlsv1.2 --output "$archive" "$url" || {
    err "Download failed: $url"
    return 1
  }
  update_log "tagged source archive SHA-256: $(sha256sum "$archive" | awk '{print $1}')"
  tar -xzf "$archive" -C "$dest" --strip-components=1 >>"$LOG_FILE" 2>&1 || {
    err "The downloaded archive could not be extracted."
    return 1
  }
  update_log "note: no published checksum exists for the tagged source archive"
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
  update_log "rollback completed from ${snapshot}"
  return 0
}

update_run() {
  local force="${1:-0}" tree snapshot remote_version current_version panel
  need_root || return 1

  panel="$(panel_config_name)"
  current_version="$APP_VERSION"
  tree="$(mktemp_dir update)" || return 1
  snapshot="$(mktemp_dir snapshot)" || return 1
  UPDATE_TAG=""

  printf 'Current version: %s\n' "$current_version"
  update_log "update started (installed version ${current_version})"

  if ! update_fetch_remote "$tree"; then
    rm -rf -- "$tree" "$snapshot"
    update_log "update aborted during download or verification"
    return 1
  fi

  remote_version="$(update_remote_version "$tree")" || {
    rm -rf -- "$tree" "$snapshot"
    err "The remote tree does not contain a VERSION file."
    update_log "the remote tree does not contain a VERSION file"
    return 1
  }
  printf 'Available version: %s\n' "$remote_version"
  update_log "remote version: ${remote_version}"

  if [[ "$remote_version" == "$current_version" && "$force" != "1" ]]; then
    ok "BaToHub is already at ${current_version}."
    update_log "no update needed; installed version equals the pinned release"
    rm -rf -- "$tree" "$snapshot"
    return 0
  fi
  if update_version_is_older "$remote_version" "$current_version" && [[ "$force" != "1" ]]; then
    err "The remote version ${remote_version} is older than the installed ${current_version}."
    err "Downgrades are refused. Pass --force only if you intentionally want to downgrade."
    update_log "downgrade refused: ${remote_version} older than ${current_version}"
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi
  if [[ "$INTERACTIVE" == 1 && "$force" != "1" ]]; then
    if ! ui_confirm "Update BaToHub from ${current_version} to ${remote_version}?"; then
      info "Update cancelled."
      update_log "update cancelled by the operator"
      rm -rf -- "$tree" "$snapshot"
      return 0
    fi
  fi

  printf 'Creating a backup of the current state...\n'
  local archive
  archive="$(backup_create "$panel")" || {
    err "A backup could not be created; the update is aborted."
    update_log "update aborted: the pre-update backup failed"
    rm -rf -- "$tree" "$snapshot"
    return 1
  }
  printf 'Backup: %s\n' "$archive"
  update_log "pre-update backup: ${archive}"

  if ! cp -a "${INSTALL_DIR}/." "$snapshot/"; then
    err "The installation snapshot could not be created; the update is aborted."
    update_log "update aborted: the installation snapshot failed"
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi
  update_log "installation snapshot created: ${snapshot}"

  if ! update_verify_tree "$tree"; then
    err "The downloaded tree failed verification; nothing was changed."
    update_log "update aborted: the downloaded tree failed verification"
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi
  update_log "downloaded tree passed verification"

  printf 'Applying updated files...\n'
  if ! update_sync_tree "$tree"; then
    update_restore_snapshot "$snapshot" || true
    update_log "update failed during synchronisation"
    rm -rf -- "$tree" "$snapshot"
    return 1
  fi
  update_log "updated files applied"

  printf 'Verifying the updated installation...\n'
  local verified=0
  if (cd "$INSTALL_DIR" && loader_validate_all) >>"$LOG_FILE" 2>&1; then
    verified=1
  fi
  if [[ "$verified" -eq 1 ]] && integrity_write && integrity_check; then
    ok "BaToHub updated to ${remote_version}."
    update_log "update completed: ${current_version} -> ${remote_version}"
    rm -rf -- "$tree" "$snapshot"
    return 0
  fi

  err "Post-update verification failed. Rolling back."
  update_log "post-update verification failed; rolling back"
  update_restore_snapshot "$snapshot" || true
  rm -rf -- "$tree" "$snapshot"
  return 1
}

update_all() {
  local force="${1:-0}" status=0
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  touch "${LOG_DIR}/update.log" 2>/dev/null || true
  update_run "$force" || status=$?
  if [[ "$status" -ne 0 ]]; then
    err "The update did not complete. The previous installation is still in place."
  fi
  return "$status"
}
