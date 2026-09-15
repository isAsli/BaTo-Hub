#!/usr/bin/env bash
set -Eeuo pipefail

# Marzban subscription template.
#
# Marzban resolves the subscription page through CUSTOM_TEMPLATES_DIRECTORY and
# SUBSCRIPTION_PAGE_TEMPLATE. BaToHub writes the template into that directory and
# records the previous file before replacing it.

MARZBAN_TEMPLATE_RELATIVE="subscription/index.html"

template_target() {
  template_target_for "${PANEL_PATH}/.env" "$MARZBAN_TEMPLATE_ROOT" "$MARZBAN_TEMPLATE_RELATIVE"
}

template_apply() {
  need_root || return 1
  local env_file target source
  env_file="${PANEL_PATH}/.env"
  [[ -f "$env_file" ]] || {
    err "Marzban configuration file was not found at ${env_file}"
    return 1
  }
  source="$(template_resolve_source)"
  [[ -n "$source" ]] || return 1
  target="$(template_target)"
  template_apply_file "$source" "$target" || return 1
  panel_env_set "$env_file" CUSTOM_TEMPLATES_DIRECTORY "$(template_root_for "$env_file" "$MARZBAN_TEMPLATE_ROOT")" || return 1
  panel_env_set "$env_file" SUBSCRIPTION_PAGE_TEMPLATE "$MARZBAN_TEMPLATE_RELATIVE" || return 1
  panel_restart_safe "$PANEL_SERVICE" || true
  ok "The BaToHub subscription template is installed for Marzban."
}

template_status() {
  template_file_status "$(template_target)" || true
  printf 'Template directory: %s\n' "$(template_root_for "${PANEL_PATH}/.env" "$MARZBAN_TEMPLATE_ROOT")"
  printf 'Subscription page option: %s\n' \
    "$(read_env_value "${PANEL_PATH}/.env" SUBSCRIPTION_PAGE_TEMPLATE 2>/dev/null || printf 'not set')"
  return 0
}

template_remove() {
  need_root || return 1
  local target
  target="$(template_target)"
  if ! ui_confirm_phrase REMOVE "Remove the BaToHub-managed template at ${target}?"; then
    return 0
  fi
  template_remove_file "$target" || true
  panel_restart_safe "$PANEL_SERVICE" || true
  return 0
}
