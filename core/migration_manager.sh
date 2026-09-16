#!/usr/bin/env bash
set -Eeuo pipefail

# The Migration section.
#
# The flow is: choose the source, choose the destination, read the source, show
# what will be created, confirm, back up both panels, write the records one at a
# time, read the destination back, and report which records could not be
# migrated and why. The source is only ever read.

migration_panel_choice() {
  local prompt="$1" panels=() name choice index=0
  shift
  while IFS= read -r name; do
    [[ -n "$name" ]] && panels+=("$name")
  done < <(loader_panels)
  ui_title "$prompt"
  for name in "${panels[@]}"; do
    index=$((index + 1))
    printf '%s) %s (%s)\n' "$index" "$(panel_display_for "$name")" "$(migration_mode "$name")"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" == 0 ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  name="${panels[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 1
  }
  printf '%s\n' "$name"
}

migration_supported_menu() {
  ui_title "Supported migrations"
  printf 'A migration copies records between two panels that publish the same shape.\n\n'
  migration_supported_pairs
  printf '\nThe pairs above are computed from the metadata of the installed panels.\n'
  printf 'A pair outside this list is refused with an explanation.\n'
  pause
}

# migration_run SOURCE DESTINATION [ASSUME_YES]
#
# The menu asks for a confirmation; a caller that has already confirmed, such as
# the command line, passes 1 and the preview is printed without a prompt.
migration_run() {
  local source="$1" destination="$2" assume_yes="${3:-0}" mode file failures count index=0 id line
  local source_backup destination_backup status=0
  need_root || return 1
  migration_pair_supported "$source" "$destination" || return 1
  mode="$(migration_mode "$source")"
  install -d -m 0750 -o root -g root "$(migration_dir)"
  file="$(mktemp "${STATE_DIR}/migrations/export.XXXXXX")"
  failures="${file}.failures"
  : >"$failures"
  chmod 0600 "$file" "$failures"

  printf 'Reading %s...\n' "$(panel_display_for "$source")"
  if ! migration_export "$source" "$file"; then
    err "The source panel could not be read, so nothing was written."
    rm -f -- "$file" "$failures"
    return 1
  fi
  printf '\n'
  migration_preview "$source" "$destination" "$file" "$mode" || {
    rm -f -- "$file" "$failures"
    return 1
  }
  printf '\n'
  if [[ "$assume_yes" != "1" ]] && ! ui_confirm "Migrate these records to $(panel_display_for "$destination")?"; then
    printf 'Nothing was migrated.\n'
    rm -f -- "$file" "$failures"
    return 0
  fi

  printf '\nBacking up both panels before anything is written...\n'
  if ! source_backup="$(backup_create "$source")"; then
    err "The source panel could not be backed up, so the migration was not started."
    rm -f -- "$file" "$failures"
    return 1
  fi
  printf 'Source backup: %s\n' "$source_backup"
  if ! destination_backup="$(backup_create "$destination")"; then
    err "The destination panel could not be backed up, so the migration was not started."
    rm -f -- "$file" "$failures"
    return 1
  fi
  printf 'Destination backup: %s\n\n' "$destination_backup"

  printf 'Writing records to %s...\n' "$(panel_display_for "$destination")"
  count="$(migration_record_count "$file")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    index=$((index + 1))
    id="$(migration_record_id "$mode" "$line")"
    if migration_create_record "$destination" "$mode" "$line"; then
      printf 'Ok   %s/%s %s\n' "$index" "$count" "${id:-<unnamed>}"
      continue
    fi
    status=1
    printf 'FAIL %s/%s %s\n' "$index" "$count" "${id:-<unnamed>}" >&2
    printf '%s\t%s\n' "${id:-<unnamed>}" "the destination refused the record" >>"$failures"
  done <"$file"

  printf '\nReading the destination back...\n'
  if migration_verify "$destination" "$mode" "$file"; then
    printf '\n'
  else
    status=1
  fi

  printf '\nReport\n'
  printf '  Source: %s (read only, nothing was changed)\n' "$(panel_display_for "$source")"
  printf '  Destination: %s\n' "$(panel_display_for "$destination")"
  printf '  Records read: %s\n' "$count"
  printf '  Source backup: %s\n' "$source_backup"
  printf '  Destination backup: %s\n' "$destination_backup"
  if [[ -s "$failures" ]]; then
    printf '  Records that could not be migrated:\n'
    while IFS=$'\t' read -r id line; do
      printf '    %s: %s\n' "$id" "$line"
    done <"$failures"
    printf '  The full report is kept at %s\n' "$failures"
  else
    printf '  Every record was created and verified.\n'
    rm -f -- "$failures"
  fi
  log "MIGRATION source=${source} destination=${destination} records=${count} status=${status}"
  rm -f -- "$file"
  return "$status"
}

migration_menu() {
  local choice source destination
  while true; do
    ui_title "Migration"
    printf 'Nothing on the source panel is changed or deleted.\n'
    printf 'Both panels are backed up before anything is written.\n\n'
    printf '1) Show the supported migrations\n'
    printf '2) Migrate between two panels\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) migration_supported_menu ;;
    2)
      source="$(migration_panel_choice 'Source panel')" || continue
      destination="$(migration_panel_choice 'Destination panel')" || continue
      migration_pair_supported "$source" "$destination" || {
        pause
        continue
      }
      migration_run "$source" "$destination" || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

migration_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  pairs) migration_supported_pairs ;;
  preview)
    need_root || return 1
    local source="${1:?source panel is required}" destination="${2:?destination panel is required}"
    local mode file
    migration_pair_supported "$source" "$destination" || return 1
    mode="$(migration_mode "$source")"
    install -d -m 0750 -o root -g root "$(migration_dir)"
    file="$(mktemp "${STATE_DIR}/migrations/export.XXXXXX")"
    chmod 0600 "$file"
    migration_export "$source" "$file" || {
      rm -f -- "$file"
      return 1
    }
    migration_preview "$source" "$destination" "$file" "$mode"
    local status=$?
    rm -f -- "$file"
    return "$status"
    ;;
  run)
    need_root || return 1
    # The command itself is the confirmation, so the preview is printed and the
    # migration proceeds without a prompt.
    migration_run "${1:?source panel is required}" "${2:?destination panel is required}" 1
    ;;
  *)
    err "Unknown migration command: ${command:-<none>}"
    printf 'Migration commands: pairs, preview <source> <destination>, run <source> <destination>\n'
    return 2
    ;;
  esac
}
