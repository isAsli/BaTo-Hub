#!/usr/bin/env bash
set -Eeuo pipefail

# 3X-UI SSL.
#
# The certificate is always issued into BaToHub state storage. Whether the panel
# can be pointed at it from the command line is decided by a runtime probe of the
# installed x-ui CLI. When the probe fails, the operator is told what to do
# instead of being shown a change that never happened.

ssl_reload_command() { printf 'systemctl try-restart %s\n' "$PANEL_SERVICE"; }

ssl_register_with_panel() {
  local cert="${1}/fullchain.pem" key="${1}/privkey.pem" cli
  if ! cli="$(xui_cli_path)"; then
    warn "The x-ui command line tool was not found."
    ssl_print_manual_instructions "$cert" "$key"
    return 0
  fi
  if ! xui_cli_supports "$cli" webCert; then
    warn "The installed x-ui version does not advertise certificate options on its CLI."
    ssl_print_manual_instructions "$cert" "$key"
    return 0
  fi
  if "$cli" setting -webCert "$cert" -webCertKey "$key" >>"$LOG_FILE" 2>&1; then
    ok "The panel CLI accepted the certificate paths."
    panel_restart_safe "$PANEL_SERVICE" || true
  else
    err "The panel CLI refused the certificate paths. Full output: ${LOG_FILE}"
    ssl_print_manual_instructions "$cert" "$key"
  fi
  return 0
}

ssl_issue() {
  need_root || return 1
  local domain email cert_dir
  domain="$(trim "$(ui_prompt 'Domain for 3X-UI (its DNS record must already point here): ' '')")"
  email="$(trim "$(ui_prompt 'Email address for the ACME account: ' '')")"
  ssl_target_validate "$domain" 0 || return 1
  ssl_dns_check "$domain" 0 || return 1
  cert_dir="$(ssl_cert_dir_for "$domain")"
  ssl_issue_cert "$domain" "$cert_dir" "$(ssl_reload_command)" 0 "$email" || return 1
  ssl_register_with_panel "$cert_dir"
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
    warn "No BaToHub-managed certificate was found for 3X-UI."
    return 1
  fi
  return 0
}

ssl_remove() {
  need_root || return 1
  local dir count=0
  if ! ui_confirm_phrase REMOVE 'Remove BaToHub-managed 3X-UI certificate files?'; then
    return 0
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_remove_pair "$dir" || true
    count=$((count + 1))
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ "$count" -eq 0 ]]; then
    warn "There was no BaToHub-managed certificate to remove for 3X-UI."
    return 0
  fi
  warn "The certificate settings inside the panel database were not modified."
  return 0
}
