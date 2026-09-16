#!/usr/bin/env bash
set -Eeuo pipefail

# Multi-domain SSL.
#
# One panel can serve more than one name: its own administration domain, its
# subscription domain, and any additional name the operator uses. Each name is
# registered per panel in ${CONFIG_DIR}/ssl/<panel>.conf with mode 0600, so the
# certificate layout of one panel is never inferred from another's.
#
# A name that needs a wildcard cannot be validated over HTTP-01, so a wildcard
# entry switches to DNS-01 and requires the provider API in
# ${CONFIG_DIR}/ssl/dns.conf. Provider credentials are exported into the acme.sh
# process environment from that file: they are never passed on a command line and
# never printed.
#
# Every issuance, renewal and revocation is appended to ${LOG_DIR}/ssl.log with a
# timestamp.

SSL_LOG="${LOG_DIR}/ssl.log"
SSL_CONFIG_DIR="${CONFIG_DIR}/ssl"
SSL_DNS_CONF="${SSL_CONFIG_DIR}/dns.conf"

ssl_log() {
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*" >>"$SSL_LOG" 2>/dev/null || true
  log "SSL $*"
}

ssl_config_path() { printf '%s/%s.conf\n' "$SSL_CONFIG_DIR" "${1:?panel name is required}"; }

ssl_purpose_valid() {
  case "${1:-}" in
  panel | subscription | custom) return 0 ;;
  *) return 1 ;;
  esac
}

ssl_method_valid() {
  case "${1:-}" in
  http-01 | dns-01 | self-signed) return 0 ;;
  *) return 1 ;;
  esac
}

# A wildcard name cannot be validated over HTTP-01.
ssl_needs_dns() {
  case "${1:-}" in
  \*.* | *'*'*) return 0 ;;
  *) return 1 ;;
  esac
}

ssl_config_ensure() {
  local panel="$1" path
  install -d -m 0750 -o root -g root "$SSL_CONFIG_DIR"
  path="$(ssl_config_path "$panel")"
  if [[ ! -f "$path" ]]; then
    atomic_write "$path" 0600 "# BaToHub SSL entries for panel ${panel}.
# One entry per line: <name> <purpose> <method> <issued-at> <fingerprint>
# purpose: panel, subscription, custom. method: http-01, dns-01, self-signed.
"
  fi
  harden_file "$path" 0600
  return 0
}

ssl_domains_list() {
  local panel="$1" path
  path="$(ssl_config_path "$panel")"
  [[ -r "$path" ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$path" || true
}

ssl_domain_entry() {
  local panel="$1" name="$2" path
  path="$(ssl_config_path "$panel")"
  [[ -r "$path" ]] || return 1
  awk -v want="$name" '$1 == want { print; exit }' "$path"
}

ssl_domain_registered() {
  local entry
  entry="$(ssl_domain_entry "$1" "$2")" || return 1
  [[ -n "$entry" ]]
}

# Refuses a name that is already registered for another panel. Two panels with
# different web servers must not serve the same certificate directory, so the
# conflict is reported rather than resolved silently.
ssl_domain_conflict() {
  local panel="$1" name="$2" other entry
  while IFS= read -r other; do
    [[ -n "$other" ]] || continue
    [[ "$other" == "$panel" ]] && continue
    entry="$(ssl_domain_entry "$other" "$name")" || continue
    if [[ -n "$entry" ]]; then
      err "The name ${name} is already registered for panel ${other}."
      err "Each panel keeps its own certificate directory, so the same name cannot be served by two of them."
      return 1
    fi
  done < <(panels_all)
  return 0
}

ssl_domain_add() {
  local panel="$1" name="$2" purpose="${3:-custom}" method="${4:-http-01}"
  local path entry
  valid_domain "$name" || {
    err "Invalid domain name: $name"
    return 1
  }
  ssl_purpose_valid "$purpose" || {
    err "Invalid purpose: $purpose (panel, subscription or custom)"
    return 1
  }
  ssl_method_valid "$method" || {
    err "Invalid method: $method (http-01, dns-01 or self-signed)"
    return 1
  }
  ssl_config_ensure "$panel" || return 1
  if entry="$(ssl_domain_entry "$panel" "$name")" && [[ -n "$entry" ]]; then
    err "The name ${name} is already registered for panel ${panel}."
    return 1
  fi
  ssl_domain_conflict "$panel" "$name" || return 1
  path="$(ssl_config_path "$panel")"
  printf '%s %s %s - -\n' "$name" "$purpose" "$method" >>"$path"
  harden_file "$path" 0600
  ssl_log "registered panel=${panel} name=${name} purpose=${purpose} method=${method}"
  ok "Registered ${name} (${purpose}, ${method}) for ${panel}."
  return 0
}

ssl_domain_record_issued() {
  local panel="$1" name="$2" fingerprint="$3" path tmp
  path="$(ssl_config_path "$panel")"
  tmp="$(mktemp_file ssl)"
  awk -v want="$name" -v stamp="$(date '+%F %T')" -v print="$fingerprint" '
    $1 == want { printf "%s %s %s %s %s\n", $1, $2, $3, stamp, print; next }
    { print }
  ' "$path" >"$tmp"
  chmod 0600 "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$path"
  harden_file "$path" 0600
  return 0
}

ssl_domain_unregister() {
  local panel="$1" name="$2" path tmp
  path="$(ssl_config_path "$panel")"
  [[ -r "$path" ]] || return 1
  tmp="$(mktemp_file ssl)"
  awk -v want="$name" '$1 != want' "$path" >"$tmp"
  chmod 0600 "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$path"
  harden_file "$path" 0600
  ssl_log "unregistered panel=${panel} name=${name}"
  return 0
}

# The DNS provider configuration is a shell assignment file. Its values are
# exported into the acme.sh process environment and never printed.
ssl_dns_provider_configured() {
  local provider
  provider="$(read_env_value "$SSL_DNS_CONF" SSL_DNS_PROVIDER 2>/dev/null || true)"
  [[ -n "$provider" ]] || {
    err "No DNS provider is configured, so DNS-01 validation is not available."
    err "Set SSL_DNS_PROVIDER and the provider API variables in ${SSL_DNS_CONF}."
    return 1
  }
  printf '%s\n' "$provider"
}

ssl_dns_environment_read() {
  local key value
  [[ -r "$SSL_DNS_CONF" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    [[ "$key" == "SSL_DNS_PROVIDER" ]] && continue
    value="$(read_env_value "$SSL_DNS_CONF" "$key" 2>/dev/null || true)"
    [[ -n "$value" ]] || continue
    export "$key=$value"
  done < <(sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$SSL_DNS_CONF" | sort -u)
  return 0
}

ssl_issue_dns01() {
  local target="$1" cert_dir="$2" reload_cmd="$3" wildcard="${4:-0}"
  local acme provider
  acme="$(ssl_acme_path)" || {
    err "acme.sh is required to issue a certificate."
    return 1
  }
  ssl_guard_cert_dir "$cert_dir" "${PANEL_NAME:-unknown}" || return 1
  provider="$(ssl_dns_provider_configured)" || return 1
  ssl_dns_environment_read || {
    err "The DNS provider file could not be read: ${SSL_DNS_CONF}"
    return 1
  }
  install -d -m 0750 -o root -g root "$cert_dir"
  local -a args=(--issue -d "$target" --dns "$provider" --server letsencrypt)
  if [[ "$wildcard" == "1" ]]; then
    args+=(-d "*.${target#\*.}")
  fi
  ssl_log "issue dns-01 target=${target} provider=${provider}"
  if ! "$acme" "${args[@]}" >>"$LOG_FILE" 2>&1; then
    err "DNS-01 issuance failed for ${target}. Full output: ${LOG_FILE}"
    err "Check the provider API credentials in ${SSL_DNS_CONF} and the challenge record."
    return 1
  fi
  if ! "$acme" --install-cert -d "$target" \
    --key-file "${cert_dir}/privkey.pem" \
    --fullchain-file "${cert_dir}/fullchain.pem" \
    --reloadcmd "$reload_cmd" >>"$LOG_FILE" 2>&1; then
    err "DNS-01 certificate installation failed for ${target}. Full output: ${LOG_FILE}"
    return 1
  fi
  if [[ ! -s "${cert_dir}/fullchain.pem" || ! -s "${cert_dir}/privkey.pem" ]]; then
    err "acme.sh did not produce a complete certificate and key for ${target}."
    return 1
  fi
  chmod 0644 "${cert_dir}/fullchain.pem"
  chmod 0600 "${cert_dir}/privkey.pem"
  chown root:root "${cert_dir}/fullchain.pem" "${cert_dir}/privkey.pem"
  ssl_marker_write "$cert_dir" "${PANEL_NAME:-unknown}"
  ok "Certificate issued for ${target} with DNS-01."
  return 0
}

ssl_cert_fingerprint() {
  local cert="$1"
  [[ -s "$cert" ]] || return 1
  need_cmd openssl || return 1
  openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2-
}

# Renews every registered name of a panel, including the wildcard entries that
# were issued with DNS-01.
ssl_renew_registered() {
  local panel="$1" name purpose method count=0
  local acme
  acme="$(ssl_acme_path)" || {
    err "acme.sh is not installed; renewal cannot run."
    return 1
  }
  while IFS=' ' read -r name purpose method _; do
    [[ -n "$name" ]] || continue
    if [[ "$method" == "self-signed" ]]; then
      warn "Skipping ${name}: a self-signed certificate is not renewable."
      continue
    fi
    ssl_log "renew target=${name} panel=${panel}"
    if "$acme" --renew -d "$name" --force >>"$LOG_FILE" 2>&1; then
      ok "Renewed: ${name}"
      count=$((count + 1))
    else
      err "Renewal failed: ${name}. Full output: ${LOG_FILE}"
    fi
  done < <(ssl_domains_list "$panel")
  if [[ "$count" -eq 0 ]]; then
    warn "No certificate registered for ${panel} was renewed."
    return 1
  fi
  return 0
}

# Revocation removes the certificate from the certificate authority and from
# acme.sh, and leaves the BaToHub entry in place so the operator decides whether
# the name stays registered.
ssl_revoke_registered() {
  local panel="$1" name acme
  acme="$(ssl_acme_path)" || {
    err "acme.sh is not installed; revocation cannot run."
    return 1
  }
  name="$(trim "$(ui_prompt 'Domain to revoke: ' '')")"
  ssl_domain_registered "$panel" "$name" || {
    err "The name ${name} is not registered for ${panel}."
    return 1
  }
  printf 'The certificate of %s is revoked at the certificate authority and removed\n' "$name"
  printf 'from acme.sh. The BaToHub entry stays registered.\n\n'
  if ! ui_confirm_phrase REVOKE 'Revoke this certificate?'; then
    printf 'Nothing was revoked.\n'
    return 0
  fi
  ssl_log "revoke target=${name} panel=${panel}"
  if ! "$acme" --revoke -d "$name" --ecc >>"$LOG_FILE" 2>&1; then
    err "Revocation failed for ${name}. Full output: ${LOG_FILE}"
    return 1
  fi
  "$acme" --remove -d "$name" --ecc >>"$LOG_FILE" 2>&1 || {
    warn "The certificate was revoked but acme.sh kept its entry."
  }
  ok "Certificate of ${name} revoked."
  return 0
}
