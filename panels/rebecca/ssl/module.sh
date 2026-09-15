#!/usr/bin/env bash
set -Eeuo pipefail

# Rebecca SSL.
#
# Certificates are issued with acme.sh into BaToHub state storage, which keeps
# Rebecca certificates separate from every other panel. acme.sh records the
# reload command per certificate, so a renewal for Rebecca never triggers a
# reload of another panel.

REBECCA_SSL_KEY_CANDIDATES=(
  SSL_CERTFILE
  UVICORN_SSL_CERTFILE
  TLS_CERT_FILE
  CERTIFICATE_FILE
)

ssl_reload_command() {
  if service_registered "$PANEL_SERVICE"; then
    printf 'systemctl try-restart %s\n' "$PANEL_SERVICE"
    return 0
  fi
  printf 'true\n'
}

ssl_rebecca_register() {
  local cert="${1}/fullchain.pem" key="${1}/privkey.pem" updated=0
  if rebecca_uses_compose; then
    warn "Rebecca runs from Docker Compose, so BaToHub did not modify the compose file."
    printf 'The certificate is stored at:\n  %s\n  %s\n' "$cert" "$key"
    printf 'Mount or copy these files in the compose stack to serve them.\n'
    install -d -m 0750 -o root -g root "$PANEL_SSL_DIR"
    printf 'certificate=%s\nkey=%s\ndomain=%s\npanel=rebecca\n' "$cert" "$key" "${SSL_TARGET:-unknown}" \
      >"${PANEL_SSL_DIR}/panel-ssl.paths"
    harden_file "${PANEL_SSL_DIR}/panel-ssl.paths" 0640
    return 0
  fi
  if [[ -f "${PANEL_PATH}/.env" ]]; then
    if ssl_register_env_keys "${PANEL_PATH}/.env" "$cert" "$key" "${REBECCA_SSL_KEY_CANDIDATES[@]}"; then
      updated=1
    fi
  else
    warn "Rebecca configuration file was not found at ${PANEL_PATH}/.env"
    ssl_print_manual_instructions "$cert" "$key"
  fi
  if [[ "$updated" -eq 1 ]]; then
    panel_restart_safe "$PANEL_SERVICE" || true
  fi
  return 0
}

ssl_issue() {
  need_root || return 1
  local domain email cert_dir
  if rebecca_uses_compose; then
    warn "Rebecca is installed as a Docker Compose stack. BaToHub issues a certificate"
    warn "and reports the paths, but it does not edit the compose file."
  fi
  domain="$(trim "$(ui_prompt 'Domain for Rebecca (its DNS record must already point here): ' '')")"
  email="$(trim "$(ui_prompt 'Email address for the ACME account: ' '')")"
  ssl_target_validate "$domain" 0 || return 1
  ssl_dns_check "$domain" 0 || return 1
  cert_dir="$(ssl_cert_dir_for "$domain")"
  ssl_issue_cert "$domain" "$cert_dir" "$(ssl_reload_command)" 0 "$email" || return 1
  ssl_rebecca_register "$cert_dir"
}

ssl_renew() {
  need_root || return 1
  if ! ssl_renew_all_for_panel; then
    warn "No BaToHub-managed certificate was renewed."
    return 1
  fi
  if service_registered "$PANEL_SERVICE"; then
    panel_restart_safe "$PANEL_SERVICE" || true
  fi
  printf 'acme.sh also renews this certificate through its own scheduled task.\n'
  return 0
}

ssl_status() {
  local paths="${PANEL_SSL_DIR}/panel-ssl.paths" cert key found=0 dir
  if [[ -r "$paths" ]]; then
    cert="$(read_env_value "$paths" certificate || true)"
    key="$(read_env_value "$paths" key || true)"
    if [[ -n "$cert" && -n "$key" ]]; then
      ssl_status_pair "$cert" "$key"
      found=1
    fi
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_status_pair "${dir}/fullchain.pem" "${dir}/privkey.pem" || true
    found=1
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ "$found" -eq 0 ]]; then
    warn "No BaToHub-managed certificate was found for Rebecca."
    return 1
  fi
  return 0
}

ssl_remove() {
  need_root || return 1
  local dir count=0
  if ! ui_confirm_phrase REMOVE 'Remove BaToHub-managed Rebecca certificate files?'; then
    return 0
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_remove_pair "$dir" || true
    count=$((count + 1))
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  rm -f -- "${PANEL_SSL_DIR}/panel-ssl.paths"
  if [[ "$count" -eq 0 ]]; then
    warn "There was no BaToHub-managed certificate to remove for Rebecca."
    return 0
  fi
  warn "Certificate options inside the Rebecca configuration were left unchanged."
  warn "Remove or replace them manually if the panel should stop serving TLS."
  return 0
}
