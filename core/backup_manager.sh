#!/usr/bin/env bash
set -Eeuo pipefail

# Backup, restore and import menus. The primitives live in lib/backup_helpers.sh.

backup_menu() {
  local choice archive
  while true; do
    ui_title "Backup"
    printf 'Backup directory: %s\n' "$BACKUP_DIR"
    printf 'Backups kept: %s\n\n' "$BACKUP_KEEP"
    printf '1) Create a backup\n'
    printf '2) List backups\n'
    printf '3) Restore a backup\n'
    printf '4) Import a backup file\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      archive="$(backup_create "$(panel_config_name)")" || {
        pause
        continue
      }
      ok "Backup created: ${archive}"
      pause
      ;;
    2)
      backup_list || true
      pause
      ;;
    3) restore_menu ;;
    4) import_menu ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

backup_choose() {
  local files=() file index=0 choice
  if ! backup_list; then
    return 1
  fi
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' 2>/dev/null | sort)
  [[ "${#files[@]}" -gt 0 ]] || {
    warn "No backup archive is available."
    return 1
  }
  printf '\n'
  for file in "${files[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$(basename "$file")"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice 'Archive: ')"
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  [[ "$choice" == 0 ]] && return 1
  archive_path="${files[$((choice - 1))]:-}"
  [[ -n "$archive_path" ]] || {
    warn "Invalid selection."
    return 1
  }
  return 0
}

restore_menu() {
  local archive_path=""
  ui_title "Restore a backup"
  if ! backup_choose; then
    pause
    return 0
  fi
  printf '\nSelected: %s\n' "$archive_path"
  printf 'Restoring writes only the paths declared in the backup metadata.\n'
  printf 'A safety backup of the current state is created first.\n\n'
  if ! ui_confirm_phrase RESTORE 'Restore this backup?'; then
    return 0
  fi
  backup_restore "$archive_path" "$(panel_config_name)" || true
  pause
}

# The managed panel is passed by the menu in core/main.sh.
# shellcheck disable=SC2120
import_menu() {
  local source=""
  ui_title "Import a backup file"
  printf 'Enter the path of a backup archive to import into %s.\n\n' "$BACKUP_DIR"
  source="$(ui_prompt 'Archive path: ' '')"
  source="$(trim "$source")"
  if [[ -z "$source" ]]; then
    warn "No path was provided."
    return 0
  fi
  if [[ "${source#/}" == "$source" ]]; then
    source="$(pwd)/${source}"
  fi
  if ! backup_import "$source" "${1:-$(panel_config_name)}"; then
    pause
    return 0
  fi
  pause
}
