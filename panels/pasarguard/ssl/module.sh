#!/usr/bin/env bash
set -Eeuo pipefail

# PasarGuard SSL.
#
# Certificates are issued into BaToHub state storage and the option names that
# the panel already declares in its .env file are updated. Unknown options are
# never appended, because an unused option would look like a working change.

PASARGUARD_SSL_KEY_CANDIDATES=(
  UVICORN_SSL_CERTFILE
  SSL_CERTFILE
  PANEL_SSL_CERTFILE
)

ssl_reload_command() { printf 'systemctl try-restart %s\n' "$PANEL_SERVICE"; }

ssl_pasarguard_register() {
  local cert="${1}/fullchain.pem" key="${1}/privkey.pem" env_file="${PANEL_PATH}/.env"
  if [[ ! -f "$env_file" ]]; then
    warn "PasarGuard configuration file was not found at ${env_file}"
    ssl_print_manual_instructions "$cert" "$key"
    return 0
  fi
  if ssl_register_env_keys "$env_file" "$cert" "$key" "${PASARGUARD_SSL_KEY_CANDIDATES[@]}"; then
    panel_restart_safe "$PANEL_SERVICE" || true
    ok "PasarGuard now reads the certificate from ${cert}."
  fi
  return 0
}

ssl_issue() {
  need_root || return 1
  local domain email cert_dir
  domain="$(trim "$(ui_prompt 'Domain for PasarGuard (its DNS record must already point here): ' '')")"
  email="$(trim "$(ui_prompt 'Email address for the ACME account: ' '')")"
  ssl_target_validate "$domain" 0 || return 1
  ssl_dns_check "$domain" 0 || return 1
  cert_dir="$(ssl_cert_dir_for "$domain")"
  ssl_issue_cert "$domain" "$cert_dir" "$(ssl_reload_command)" 0 "$email" || return 1
  ssl_pasarguard_register "$cert_dir"
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
    warn "No BaToHub-managed certificate was found for PasarGuard."
    return 1
  fi
  return 0
}

ssl_remove() {
  need_root || return 1
  local dir count=0
  if ! ui_confirm_phrase REMOVE 'Remove BaToHub-managed PasarGuard certificate files?'; then
    return 0
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_remove_pair "$dir" || true
    count=$((count + 1))
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ "$count" -eq 0 ]]; then
    warn "There was no BaToHub-managed certificate to remove for PasarGuard."
    return 0
  fi
  warn "Certificate options inside the PasarGuard configuration were left unchanged."
  return 0
}
