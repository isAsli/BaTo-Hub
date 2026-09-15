#!/usr/bin/env bash
set -Eeuo pipefail

# Rebecca subscription template.
#
# The bundled template is copied into the directory Rebecca already uses for
# custom templates, and the two documented options in .env are updated. The
# previous file is always copied into BaToHub state storage first.

template_target() {
  template_target_for "${PANEL_PATH}/.env" "$REBECCA_TEMPLATE_ROOT" "subscription/index.html"
}

template_env_file() { printf '%s\n' "${PANEL_PATH}/.env"; }

template_apply() {
  need_root || return 1
  local env_file target source
  env_file="$(template_env_file)"
  [[ -f "$env_file" ]] || {
    err "Rebecca configuration file was not found at ${env_file}"
    return 1
  }
  source="$(template_resolve_source)"
  [[ -n "$source" ]] || return 1
  target="$(template_target)"
  template_apply_file "$source" "$target" || return 1
  panel_env_set "$env_file" CUSTOM_TEMPLATES_DIRECTORY "$(dirname "$(dirname "$target")")" || return 1
  panel_env_set "$env_file" SUBSCRIPTION_PAGE_TEMPLATE "subscription/index.html" || return 1
  if rebecca_uses_compose; then
    warn "Rebecca runs from Docker Compose; mount ${REBECCA_TEMPLATE_ROOT} into the container to serve the template."
  else
    panel_restart_safe "$PANEL_SERVICE" || true
  fi
  ok "BaTo-Ui is installed for Rebecca."
}

template_status() {
  local target
  target="$(template_target)"
  template_file_status "$target" || true
  printf 'Template directory: %s\n' "$(template_root_for "${PANEL_PATH}/.env" "$REBECCA_TEMPLATE_ROOT")"
  printf 'Subscription page option: %s\n' \
    "$(read_env_value "${PANEL_PATH}/.env" SUBSCRIPTION_PAGE_TEMPLATE 2>/dev/null || printf 'not set')"
  if [[ -d "${STATE_DIR}/templates-backup" ]]; then
    printf 'Previous templates kept in: %s\n' "${STATE_DIR}/templates-backup"
  fi
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
  if rebecca_uses_compose; then
    warn "Rebecca runs from Docker Compose; nothing was restarted."
  else
    panel_restart_safe "$PANEL_SERVICE" || true
  fi
  return 0
}
