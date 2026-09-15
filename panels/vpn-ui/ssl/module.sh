#!/usr/bin/env bash
set -Eeuo pipefail

# VPN-UI SSL.
#
# VPN-UI is the one supported panel that can serve a certificate for a bare
# address, so `ssl_issue` accepts either a domain name or an IPv4 address. The
# certificate always lands in BaToHub state storage; the panel CLI is used only
# when it reports certificate support.

ssl_reload_command() { printf 'systemctl try-restart %s\n' "$PANEL_SERVICE"; }

ssl_register_with_panel() {
  local cert="${1}/fullchain.pem" key="${1}/privkey.pem" binary
  if ! binary="$(vpnui_binary)"; then
    warn "The VPN-UI binary was not found."
    ssl_print_manual_instructions "$cert" "$key"
    return 0
  fi
  if ! "$binary" --help 2>&1 | grep -q -- 'webCert'; then
    warn "This VPN-UI build does not advertise certificate options on its command line."
    ssl_print_manual_instructions "$cert" "$key"
    return 0
  fi
  if "$binary" setting -webCert "$cert" -webCertKey "$key" >>"$LOG_FILE" 2>&1; then
    ok "The panel accepted the certificate paths."
    panel_restart_safe "$PANEL_SERVICE" || true
  else
    err "The panel refused the certificate paths. Full output: ${LOG_FILE}"
    ssl_print_manual_instructions "$cert" "$key"
  fi
  return 0
}

ssl_issue() {
  need_root || return 1
  local target email cert_dir allow_ip=0
  printf 'VPN-UI can use a domain name or a bare address.\n'
  target="$(trim "$(ui_prompt 'Domain or public IPv4 address for VPN-UI: ' '')")"
  if valid_ipv4 "$target"; then
    allow_ip=1
    printf 'A certificate for a bare address is only useful with a client that trusts it.\n'
  fi
  email="$(trim "$(ui_prompt 'Email address for the ACME account: ' '')")"
  ssl_target_validate "$target" "$allow_ip" || return 1
  ssl_dns_check "$target" "$allow_ip" || return 1
  cert_dir="$(ssl_cert_dir_for "$target")"
  ssl_issue_cert "$target" "$cert_dir" "$(ssl_reload_command)" "$allow_ip" "$email" || return 1
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
    warn "No BaToHub-managed certificate was found for VPN-UI."
    return 1
  fi
  return 0
}

ssl_remove() {
  need_root || return 1
  local dir count=0
  if ! ui_confirm_phrase REMOVE 'Remove BaToHub-managed VPN-UI certificate files?'; then
    return 0
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "$PANEL_NAME" ]] || continue
    ssl_remove_pair "$dir" || true
    count=$((count + 1))
  done < <(find "$PANEL_SSL_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [[ "$count" -eq 0 ]]; then
    warn "There was no BaToHub-managed certificate to remove for VPN-UI."
    return 0
  fi
  warn "The certificate settings inside the panel database were not modified."
  return 0
}
