#!/usr/bin/env bash
set -Eeuo pipefail

# Subscription template helpers.
#
# The subscription template ships once, at templates/subscription/index.html.
# A panel may override it with its own file at
# panels/<panel>/templates/subscription/index.html, which wins when it exists.
# A template is always copied out of the BaToHub release tree into a panel
# specific directory, and the previous file is kept under BaToHub state storage
# before it is replaced, so no panel template is ever overwritten without a copy.

# Marzban family panels resolve the subscription template through two options in
# their .env file. Both are read back from the panel instead of being assumed.
template_root_for() {
  local env_file="$1" default_root="$2" root=""
  if [[ -r "$env_file" ]]; then
    root="$(read_env_value "$env_file" CUSTOM_TEMPLATES_DIRECTORY || true)"
    root="$(trim "${root:-}")"
  fi
  printf '%s\n' "${root:-$default_root}"
}

template_target_for() {
  local env_file="$1" default_root="$2" default_relative="$3" relative=""
  if [[ -r "$env_file" ]]; then
    relative="$(read_env_value "$env_file" SUBSCRIPTION_PAGE_TEMPLATE || true)"
    relative="$(trim "${relative:-}")"
  fi
  printf '%s/%s\n' "$(template_root_for "$env_file" "$default_root")" "${relative:-$default_relative}"
}

template_backup_dir() { printf '%s/templates-backup\n' "$STATE_DIR"; }

template_backup_path() {
  local target="$1"
  printf '%s/%s.%s\n' "$(template_backup_dir)" "$(basename "$(dirname "$target")")-$(basename "$target")" "$(current_timestamp)"
}

# Resolves the template file to install, in order of preference: a panel
# specific override under panels/<panel>/templates/subscription/index.html, the
# shared template at templates/subscription/index.html, or an operator supplied
# path when given at the prompt.
template_resolve_source() {
  local override="${PANEL_MODULE_DIR:-}/templates/subscription/index.html"
  local shared="${BATOHUB_ROOT:-/opt/batohub}/templates/subscription/index.html"
  local answer
  if [[ -r "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [[ -r "$shared" ]]; then
    printf '%s\n' "$shared"
    return 0
  fi
  if [[ "$INTERACTIVE" != 1 ]]; then
    err "No subscription template was found for panel ${PANEL_NAME:-unknown}."
    err "Expected the shared template at: $shared"
    err "or a panel override at: $override"
    return 1
  fi
  answer="$(trim "$(ui_prompt 'Path of the template file to install: ' '') ")"
  if [[ -z "$answer" || ! -r "$answer" ]]; then
    err "No readable template file was provided."
    return 1
  fi
  printf '%s\n' "$answer"
}

template_apply_file() {
  local source="$1" target="$2" backup
  [[ -r "$source" ]] || {
    err "Template source is missing: $source"
    return 1
  }
  case "$target" in
  /opt/* | /usr/local/* | /etc/* | "${STATE_DIR}"/*) ;;
  *)
    err "Refusing to write a template outside a declared panel path: $target"
    return 1
    ;;
  esac
  install -d -m 0750 -o root -g root "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    backup="$(template_backup_path "$target")"
    install -d -m 0750 -o root -g root "$(template_backup_dir)"
    cp -a -- "$target" "$backup"
    harden_file "$backup" 0600
    log "Template backup created: $backup"
    printf 'Previous template saved to: %s\n' "$backup"
  fi
  if ! install -m 0644 -o root -g root "$source" "$target"; then
    err "Failed to install template at $target"
    return 1
  fi
  ok "Template installed: $target"
}

template_remove_file() {
  local target="$1" backup
  case "$target" in
  /opt/* | /usr/local/* | /etc/* | "${STATE_DIR}"/*) ;;
  *)
    err "Refusing to remove a template outside a declared panel path: $target"
    return 1
    ;;
  esac
  if [[ ! -e "$target" ]]; then
    warn "Template is not installed: $target"
    return 1
  fi
  # Keep a copy before removal so the operation is reversible.
  backup="$(template_backup_path "$target")"
  install -d -m 0750 -o root -g root "$(template_backup_dir)"
  cp -a -- "$target" "$backup"
  harden_file "$backup" 0600
  rm -f -- "$target"
  ok "Template removed: $target"
  printf 'A copy was kept at: %s\n' "$backup"
}

# Some panels generate subscription pages from their own database and expose no
# documented template directory. For those panels BaToHub stages the template in
# its own state storage and states plainly that the panel was not modified.
template_staged_target() {
  printf '%s/subscription/index.html\n' "${PANEL_TEMPLATE_DIR:?panel template directory is not set}"
}

template_stage_apply() {
  local source target
  source="$(template_resolve_source)" || return 1
  target="$(template_staged_target)"
  install -d -m 0750 -o root -g root "$(dirname "$target")"
  if ! install -m 0644 -o root -g root "$source" "$target"; then
    err "The template could not be staged at $target"
    return 1
  fi
  printf 'Staged template: %s\n' "$target"
  printf 'Panel %s generates its subscription output from its own settings.\n' "${PANEL_DISPLAY:-${PANEL_NAME:-unknown}}"
  printf 'BaToHub did not modify the panel database or the panel configuration.\n'
  return 0
}

template_stage_status() {
  local target
  target="$(template_staged_target)"
  template_file_status "$target" || true
  printf 'Template method declared by this panel: %s\n' "$(panel_meta_get "${PANEL_NAME:-}" template_method)"
  return 0
}

template_stage_remove() {
  local target
  target="$(template_staged_target)"
  if ! ui_confirm_phrase REMOVE "Remove the staged template at ${target}?"; then
    return 0
  fi
  template_remove_file "$target" || true
  return 0
}

template_file_status() {
  local target="$1"
  if [[ -s "$target" ]]; then
    printf 'Template installed: %s\n' "$target"
    if need_cmd sha256sum; then
      printf 'SHA-256: %s\n' "$(sha256sum "$target" | awk '{print $1}')"
    fi
    printf 'Modified: %s\n' "$(date -r "$target" '+%F %T' 2>/dev/null || printf 'unknown')"
    return 0
  fi
  printf 'Template is not installed: %s\n' "$target"
  return 1
}
