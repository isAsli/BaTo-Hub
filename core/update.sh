#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

protected_paths_list() {
  local list
  list="${CONFIG_DIR}/panel.conf"
  list="${list}
${CONFIG_DIR}/batohub.conf"
  list="${list}
${STATE_DIR}"
  list="${list}
${LOG_DIR}"
  printf '%s' "$list"
}

protected_paths_include() {
  local path="$1"
  local list
  list=$(protected_paths_list)
  if printf '%s\n' "$list" | grep -qxF "$path"; then
    return 0
  fi
  if printf '%s\n' "$list" | grep -qF "$(dirname "$path")/"; then
    return 0
  fi
  return 1
}

update_all() {
  local remote_version tmp remote_root diff_added diff_removed diff_changed backup_dir rollback_ok new_files removed_files changed_files
  header

  info "Checking remote update from GitHub branch ${GITHUB_BRANCH:-main}..."

  remote_version=$(mktemp_file "remote_version")
  tmp=$(mktemp_file "remote_manifest")

  local repo_url="https://github.com/${GITHUB_REPO:-isAsli/BaTo-Hub}.git"
  local remote_ref="${GITHUB_BRANCH:-main}"

  (
    if command -v git >/dev/null 2>&1; then
      git ls-remote --heads "$repo_url" "$remote_ref" 2>>"$LOG_FILE" || true
    fi
  ) > "$remote_version" 2>/dev/null || true

  if [ ! -s "$remote_version" ]; then
    err "Unable to reach remote repository or branch."
    rm -f "$remote_version" "$tmp"
    pause
    return
  fi

  local remote_head
  remote_head=$(awk '{print $1}' "$remote_version" | head -n 1)

  if [ -z "$remote_head" ]; then
    err "Remote branch reference not found: $remote_ref"
    rm -f "$remote_version" "$tmp"
    pause
    return
  fi

  # Fetch remote tree into a temporary location.
  remote_root=$(mktemp_dir "remote_root")
  (
    cd "$remote_root"
    if command -v git >/dev/null 2>&1; then
      git init --quiet
      git remote add origin "$repo_url"
      git fetch --depth=1 origin "$remote_ref" 2>>"$LOG_FILE" || true
      git checkout -b update_candidate FETCH_HEAD 2>>"$LOG_FILE" || true
    else
      err "git is required for update."
      rm -rf "$remote_root"
      exit 1
    fi
  ) || {
    err "Failed to prepare remote tree."
    rm -rf "$remote_root"
    rm -f "$remote_version" "$tmp"
    pause
    return
  }

  local local_version remote_version_value
  local_version="$APP_VERSION"
  remote_version_value=$(cat "${remote_root}/VERSION" 2>/dev/null | sed -n '1p' | tr -d '[:space:]' || true)

  if [ -z "$remote_version_value" ]; then
    err "Remote VERSION file not found."
    rm -rf "$remote_root"
    rm -f "$remote_version" "$tmp"
    pause
    return
  fi

  if [ "$local_version" = "$remote_version_value" ]; then
    ok "BaToHub is up to date: $local_version"
    rm -rf "$remote_root"
    rm -f "$remote_version" "$tmp"
    pause
    return
  fi

  info "Local version: $local_version"
  info "Remote version: $remote_version_value"

  if ! confirm "Update to $remote_version_value? This will replace managed files."; then
    rm -rf "$remote_root"
    rm -f "$remote_version" "$tmp"
    return
  fi

  # Full backup before update.
  backup_dir=$(mktemp_dir "update_backup")
  cp -a "${INSTALL_DIR:-/opt/batohub}" "$backup_dir/install"
  cp -a "${CONFIG_DIR:-/etc/batohub}" "$backup_dir/config" 2>/dev/null || true
  cp -a "${STATE_DIR:-/var/lib/batohub}" "$backup_dir/state" 2>/dev/null || true
  cp -a "${LOG_DIR:-/var/log/batohub}" "$backup_dir/logs" 2>/dev/null || true

  # Determine changed files.
  diff_added=$(mktemp_file "added")
  diff_removed=$(mktemp_file "removed")
  diff_changed=$(mktemp_file "changed")

  (
    cd "${INSTALL_DIR:-/opt/batohub}"
    git status --porcelain -uall 2>/dev/null | awk '{print $2}' || true
  ) > /dev/null 2>&1 || true

  # Compare local tracked files against remote tree.
  if command -v git >/dev/null 2>&1; then
    cd "$remote_root"
    git ls-tree -r --name-only HEAD 2>/dev/null | sort > "$tmp"
    cd "${INSTALL_DIR:-/opt/batohub}"
    find . -type f -not -path './.*' | sed 's|^\./||' | sort > "${tmp}.local"

    comm -23 "${tmp}.local" "$tmp" > "$diff_removed" || true
    comm -13 "${tmp}.local" "$tmp" > "$diff_added" || true
    comm -12 "${tmp}.local" "$tmp" | while read -r f; do
      if ! cmp -s "$f" "$remote_root/$f" 2>/dev/null; then
        printf '%s\n' "$f" >> "$diff_changed"
      fi
    done
  else
    info "git diff unavailable; applying full managed replacement."
    diff_added=$(mktemp_file "added_fallback")
    diff_changed=$(mktemp_file "changed_fallback")
  fi

  # Apply update safely.
  local install_dir="${INSTALL_DIR:-/opt/batohub}"
  local backup_install="${backup_dir}/install"
  local backup_config="${backup_dir}/config"
  local backup_state="${backup_dir}/state"
  local backup_logs="${backup_dir}/logs"

  # Replace managed tree.
  rm -rf "$install_dir.new"
  cp -a "$remote_root" "$install_dir.new"

  # Restore protected paths from the old installation where they existed.
  if [ -d "$backup_config" ] && [ -f "$backup_config/panel.conf" ]; then
    install -d "$install_dir.new/etc/batohub" 2>/dev/null || true
    cp -a "$backup_config/panel.conf" "$install_dir.new/etc/batohub/panel.conf" 2>/dev/null || true
    cp -a "$backup_config/batohub.conf" "$install_dir.new/etc/batohub/batohub.conf" 2>/dev/null || true
  fi

  if [ -d "$backup_state" ]; then
    cp -a "$backup_state" "$install_dir.new/var/lib/batohub" 2>/dev/null || true
  fi

  if [ -d "$backup_logs" ]; then
    cp -a "$backup_logs" "$install_dir.new/var/log/batohub" 2>/dev/null || true
  fi

  local new_install_dir="$install_dir.new"

  # Verify shell sources in the new tree.
  local shell_error=0
  while IFS= read -r f; do
    if [ -f "$new_install_dir/$f" ]; then
      if ! bash -n "$new_install_dir/$f" 2>>"$LOG_FILE"; then
        err "Syntax error in updated file: $f"
        shell_error=1
      fi
    fi
  done < <(find "$new_install_dir" -type f -name '*.sh' | sed "s|^$new_install_dir/||")

  if [ "$shell_error" -ne 0 ]; then
    err "Update verification failed. Rolling back."
    rollback_ok=0
    if [ -d "$backup_install" ]; then
      rm -rf "$install_dir"
      mv "$backup_install" "$install_dir"
      rollback_ok=1
    fi
    if [ "$rollback_ok" -eq 0 ]; then
      err "Rollback also failed. Manual recovery required."
    else
      ok "Rollback completed from backup."
    fi
    rm -rf "$remote_root" "$backup_dir" "$remote_version" "$tmp" "$diff_added" "$diff_removed" "$diff_changed"
    pause
    return
  fi

  # Move updated tree into place.
  rm -rf "$install_dir"
  mv "$new_install_dir" "$install_dir"

  # Restore protected config/state/log from backup if they were present.
  if [ -d "$backup_config" ]; then
    cp -a "$backup_config"/* "$install_dir/etc/batohub/" 2>/dev/null || true
  fi
  if [ -d "$backup_state" ]; then
    cp -a "$backup_state/." "$install_dir/var/lib/batohub/" 2>/dev/null || true
  fi
  if [ -d "$backup_logs" ]; then
    cp -a "$backup_logs/." "$install_dir/var/log/batohub/" 2>/dev/null || true
  fi

  chmod 750 "$install_dir/etc/batohub" 2>/dev/null || true
  chmod 750 "$install_dir/var/lib/batohub" 2>/dev/null || true
  chmod 750 "$install_dir/var/log/batohub" 2>/dev/null || true
  chmod 600 "$install_dir/etc/batohub/panel.conf" 2>/dev/null || true
  chmod 600 "$install_dir/etc/batohub/batohub.conf" 2>/dev/null || true
  chown -R root:root "$install_dir" 2>/dev/null || true

  # Print diff summary.
  info "Update summary:"
  if [ -s "$diff_added" ]; then
    info "Added files:"
    cat "$diff_added" | sed 's|^|  + |'
  fi
  if [ -s "$diff_removed" ]; then
    info "Removed files:"
    cat "$diff_removed" | sed 's|^|  - |'
  fi
  if [ -s "$diff_changed" ]; then
    info "Changed files:"
    cat "$diff_changed" | sed 's|^|  ~ |'
  fi

  ok "BaToHub updated to $remote_version_value"
  rm -rf "$remote_root" "$backup_dir" "$remote_version" "$tmp" "$diff_added" "$diff_removed" "$diff_changed"
  pause
}
