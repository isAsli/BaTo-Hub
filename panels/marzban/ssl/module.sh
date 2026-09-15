#!/usr/bin/env bash
set -Eeuo pipefail

# Marzban SSL.
#
# Marzban serves its dashboard through uvicorn, which reads the certificate
# options from /opt/marzban/.env. Only option names that already exist in that
# file are updated; BaToHub does not append unknown options.

MARZBAN_SSL_KEY_CANDIDATES=(
  UVICORN_SSL_CERTFILE
  SSL_CERTFILE
)

ssl_reload_command() { printf 'systemctl try-restart %s\n' "$PANEL_SERVICE"; }

ssl_marzban_register() {
  local cert="${1}/fullchain.pem" key="${1}/privkey.pem" env_file="${PANEL_PATH}/.env"
  if [[ ! -f "$env_file" ]]; then
    warn "Marzban configuration file was not found at ${env_file}"
    ssl_print_manual_instructions "$cert" "$key"
    return 0
  fi
  if ssl_register_env_keys "$env_file" "$cert" "$key" "${MARZBAN_SSL_KEY_CANDIDATES[@]}"; then
    panel_restart_safe "$PANEL_SERVICE" || true
    ok "Marzban now reads the certificate from ${cert}."
  fi
  return 0
}

ssl_issue() {
  need_root || return 1
  local domain email cert_dir
  domain="$(trim "$(ui_prompt 'Domain for Marzban (its DNS record must already point here): ' '')")"
  email="$(trim "$(ui_prompt 'Email address for the ACME account: ' '')")"
  ssl_target_validate "$domain" 0 || return 1
  ssl_dns_check "$domain" 0 || return 1
  cert_dir="$(ssl_cert_dir_for "$domain")"
  ssl_issue_cert "$domain" "$cert_dir" "$(ssl_reload_command)" 0 "$email" || return 1
  ssl_marzban_register "$cert_dir"
}

ssl_renew() {
  need_root || return 1
  if ! ssl_renew_all_for_panel; then
    warn "No BaToHub-managed certificate was renewed."
    return 1
  fi
  panel_restart_safe "$PANEL_SERVICE" || true
  return 0
}

ssl_status() {
  local dir found=0
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_status_pair "${dir}/fullchain.pem" "${dir}/privkey.pem" || true
    found=1
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ "$found" -eq 0 ]]; then
    warn "No BaToHub-managed certificate was found for Marzban."
    return 1
  fi
  return 0
}

ssl_remove() {
  need_root || return 1
  local dir count=0
  if ! ui_confirm_phrase REMOVE 'Remove BaToHub-managed Marzban certificate files?'; then
    return 0
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_remove_pair "$dir" || true
    count=$((count + 1))
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ "$count" -eq 0 ]]; then
    warn "There was no BaToHub-managed certificate to remove for Marzban."
    return 0
  fi
  warn "Certificate options inside the Marzban configuration were left unchanged."
  return 0
}
