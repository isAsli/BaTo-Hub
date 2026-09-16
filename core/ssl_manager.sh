#!/usr/bin/env bash
set -Eeuo pipefail

# The SSL section: the registered names, issuance, renewal and revocation.
#
# Issuance for a registered name uses the method recorded for it. A wildcard
# switches to DNS-01 and needs the provider API; a name that is not a wildcard
# uses HTTP-01 unless DNS-01 was recorded for it explicitly.

ssl_load_panel() {
  local panel="$1"
  loader_load_panel "$panel" >/dev/null 2>&1 || {
    err "Panel could not be loaded: $panel"
    return 1
  }
  panel_submodule ssl >/dev/null 2>&1 || {
    err "Panel ${panel} has no SSL module."
    return 1
  }
  return 0
}

ssl_panel_choice() {
  local panels=() name choice index=0
  while IFS= read -r name; do
    [[ -n "$name" ]] && panels+=("$name")
  done < <(loader_panels)
  ui_title "Choose a panel"
  for name in "${panels[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$(panel_display_for "$name")"
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

ssl_domains_lines() {
  local filter="${1:-}" panel name purpose method issued cert days found=0
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    [[ -n "$filter" && "$panel" != "$filter" ]] && continue
    while IFS=' ' read -r name purpose method issued _; do
      [[ -n "$name" ]] || continue
      found=1
      # The list covers every panel, so the certificate directory is derived from
      # the panel rather than from the loaded panel context.
      cert="$(panel_ssl_dir_for "$panel")/$(ssl_target_slug "$name")/fullchain.pem"
      days="-"
      if [[ -s "$cert" ]]; then
        days="$(ssl_days_remaining "$cert" 2>/dev/null || printf 'unknown')"
      fi
      printf '  %-10s %-32s %-13s %-10s %-12s %s\n' \
        "$panel" "$name" "$purpose" "$method" "${issued:--}" "expires in ${days} days"
    done < <(ssl_domains_list "$panel")
  done < <(loader_panels)
  if [[ "$found" -eq 0 ]]; then
    printf '  No name is registered.\n'
  fi
  return 0
}

ssl_domains_menu() {
  ui_title "Registered certificate names"
  printf '  %-10s %-32s %-13s %-10s %-12s %s\n' PANEL NAME PURPOSE METHOD ISSUED EXPIRY
  ssl_domains_lines
  pause
}

ssl_register_flow() {
  local panel name purpose method
  need_root || return 1
  panel="$(ssl_panel_choice)" || return 0
  ui_title "Register a name for $(panel_display_for "$panel")"
  printf 'Purposes: panel, subscription, custom.\n'
  printf 'Methods: http-01 (a single name), dns-01 (a wildcard or a DNS record you do not want to expose), self-signed (testing).\n\n'
  name="$(trim "$(ui_prompt 'Domain: ' '')")"
  purpose="$(trim "$(ui_prompt 'Purpose [custom]: ' 'custom')")"
  method="$(trim "$(ui_prompt 'Method [http-01]: ' 'http-01')")"
  [[ -n "$purpose" ]] || purpose="custom"
  [[ -n "$method" ]] || method="http-01"
  if ssl_needs_dns "$name" && [[ "$method" == "http-01" ]]; then
    warn "A wildcard name cannot be validated over HTTP-01. Switching to DNS-01."
    method="dns-01"
  fi
  if [[ "$method" == "dns-01" ]]; then
    ssl_dns_provider_configured >/dev/null || return 1
  fi
  if ! ui_confirm "Use the BaToHub-managed certificate for ${name}?"; then
    printf 'Nothing was registered.\n'
    return 0
  fi
  ssl_domain_add "$panel" "$name" "$purpose" "$method"
  return $?
}

ssl_issue_flow() {
  local panel name purpose method cert_dir reload wildcard=0 email
  need_root || return 1
  panel="$(ssl_panel_choice)" || return 0
  ssl_load_panel "$panel" || return 1
  ui_title "Issue a certificate - $(panel_display_for "$panel")"
  ssl_domains_lines "$panel"
  name="$(trim "$(ui_prompt '\nDomain: ' '')")"
  ssl_domain_registered "$panel" "$name" || {
    err "The name ${name} is not registered for ${panel}. Register it first."
    return 1
  }
  IFS=' ' read -r _ purpose method _ _ <<<"$(ssl_domain_entry "$panel" "$name")"
  ssl_target_validate "$name" "$(panel_supports_bare_ip "$panel" && printf '1' || printf '0')" || return 1
  if ssl_needs_dns "$name"; then
    wildcard=1
    method="dns-01"
  fi
  cert_dir="$(ssl_cert_dir_for "$name")"
  reload="$(ssl_reload_command)"

  if [[ "$method" == "self-signed" ]]; then
    ssl_selfsigned_issue "$name" "$cert_dir" || return 1
    ssl_domain_record_issued "$panel" "$name" "$(ssl_cert_fingerprint "${cert_dir}/fullchain.pem" || printf 'unknown')"
    return 0
  fi

  if [[ "$method" != "dns-01" ]]; then
    ssl_dns_check "$name" 0 || return 1
    email="$(trim "$(ui_prompt 'Email address for the ACME account: ' '')")"
    ssl_issue_cert "$name" "$cert_dir" "$reload" 0 "$email" || return 1
  else
    ssl_issue_dns01 "$name" "$cert_dir" "$reload" "$wildcard" || return 1
  fi
  ssl_domain_record_issued "$panel" "$name" "$(ssl_cert_fingerprint "${cert_dir}/fullchain.pem" || printf 'unknown')"
  return 0
}

ssl_renew_flow() {
  local panel
  need_root || return 1
  panel="$(ssl_panel_choice)" || return 0
  ssl_load_panel "$panel" || return 1
  ui_title "Renew certificates - $(panel_display_for "$panel")"
  ssl_renew_registered "$panel" || true
  return 0
}

ssl_unregister_flow() {
  local panel name purpose method
  need_root || return 1
  panel="$(ssl_panel_choice)" || return 0
  ui_title "Remove a BaToHub-managed certificate - $(panel_display_for "$panel")"
  ssl_domains_lines "$panel"
  name="$(trim "$(ui_prompt '\nDomain: ' '')")"
  ssl_domain_registered "$panel" "$name" || {
    err "The name ${name} is not registered for ${panel}."
    return 1
  }
  IFS=' ' read -r _ purpose method _ _ <<<"$(ssl_domain_entry "$panel" "$name")"
  if ! ui_confirm_phrase REMOVE "Remove the BaToHub-managed certificate of ${name}?"; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  ssl_remove_pair "$(ssl_cert_dir_for "$name")" || true
  ssl_domain_unregister "$panel" "$name"
  warn "Certificate options inside the panel configuration were left unchanged."
  return 0
}

ssl_menu_multi() {
  local choice
  while true; do
    ui_title "SSL"
    printf '1) Show registered names\n'
    printf '2) Register a name\n'
    printf '3) Issue a certificate\n'
    printf '4) Renew the certificates of one panel\n'
    printf '5) Revoke a certificate\n'
    printf '6) Remove a BaToHub-managed certificate\n'
    printf '7) Certificate status\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) ssl_domains_menu ;;
    2)
      ssl_register_flow || true
      pause
      ;;
    3)
      ssl_issue_flow || true
      pause
      ;;
    4)
      ssl_renew_flow || true
      pause
      ;;
    5)
      ssl_panel_choice >/dev/null 2>&1 || true
      warn "Choose the panel first, then the domain."
      panel=""
      ;;
    6)
      ssl_unregister_flow || true
      pause
      ;;
    7)
      panel="$(ssl_panel_choice)" || continue
      ssl_load_panel "$panel" || continue
      ui_title "Certificate status - $(panel_display_for "$panel")"
      ssl_status || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

ssl_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  list)
    printf '  %-10s %-32s %-13s %-10s %-12s %s\n' PANEL NAME PURPOSE METHOD ISSUED EXPIRY
    ssl_domains_lines "${1:-}"
    ;;
  register)
    need_root || return 1
    ssl_domain_add "${1:?panel is required}" "${2:?domain is required}" "${3:-custom}" "${4:-http-01}"
    ;;
  unregister)
    need_root || return 1
    ssl_domain_unregister "${1:?panel is required}" "${2:?domain is required}" || return 1
    ok "Removed ${2} from the SSL configuration of ${1}."
    ;;
  renew)
    need_root || return 1
    local panel="${1:-}"
    local -a targets=()
    if [[ -n "$panel" ]]; then
      targets=("$panel")
    else
      while IFS= read -r name; do
        [[ -n "$name" ]] && targets+=("$name")
      done < <(loader_panels)
    fi
    local failed=0 name
    for name in "${targets[@]}"; do
      ssl_load_panel "$name" || {
        failed=1
        continue
      }
      ssl_renew_registered "$name" || failed=1
    done
    return "$failed"
    ;;
  status)
    local panel="${1:?panel is required}"
    ssl_load_panel "$panel" || return 1
    ssl_status
    ;;
  revoke)
    need_root || return 1
    local panel="${1:?panel is required}" domain="${2:?domain is required}"
    ssl_load_panel "$panel" || return 1
    ssl_domain_registered "$panel" "$domain" || {
      err "The name ${domain} is not registered for ${panel}."
      return 1
    }
    local acme
    acme="$(ssl_acme_path)" || return 1
    ssl_log "revoke target=${domain} panel=${panel}"
    "$acme" --revoke -d "$domain" --ecc >>"$LOG_FILE" 2>&1 || {
      err "Revocation failed for ${domain}. Full output: ${LOG_FILE}"
      return 1
    }
    "$acme" --remove -d "$domain" --ecc >>"$LOG_FILE" 2>&1 || true
    ok "Certificate of ${domain} revoked."
    ;;
  *)
    err "Unknown ssl command: ${command:-<none>}"
    printf 'SSL commands: list, register, unregister, renew, status, revoke\n'
    return 2
    ;;
  esac
}
