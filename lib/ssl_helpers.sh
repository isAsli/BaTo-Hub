#!/usr/bin/env bash
set -Eeuo pipefail

# SSL helpers.
#
# Every certificate lives below ${STATE_DIR}/panels/<panel>/ssl/<target>/, so two
# panels can never share a certificate directory or a renewal hook. acme.sh
# stores the reload command per certificate, which keeps panel reload actions
# from overlapping. A marker file records which panel owns a certificate
# directory; BaToHub refuses to touch a directory that belongs to another panel.

SSL_ACME_BIN="${SSL_ACME_BIN:-$HOME/.acme.sh/acme.sh}"

ssl_acme_path() {
  if [[ -x "$SSL_ACME_BIN" ]]; then
    printf '%s\n' "$SSL_ACME_BIN"
    return 0
  fi
  if need_cmd acme.sh; then
    command -v acme.sh
    return 0
  fi
  return 1
}

ssl_target_validate() {
  local target="$1" allow_ip="${2:-0}"
  if [[ -z "$target" ]]; then
    err "A domain name is required."
    return 1
  fi
  if [[ "$allow_ip" == "1" ]] && valid_ipv4 "$target"; then
    return 0
  fi
  if ! valid_domain "$target"; then
    err "Invalid domain name: $target"
    return 1
  fi
  if valid_ipv4 "$target"; then
    err "This panel requires a domain name; an IP address cannot be used: $target"
    return 1
  fi
  return 0
}

ssl_target_slug() {
  printf '%s\n' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
}

ssl_cert_dir_for() {
  local target="$1"
  printf '%s/%s\n' "${PANEL_SSL_DIR:?panel SSL directory is not set}" "$(ssl_target_slug "$target")"
}

ssl_marker_path() { printf '%s/.batohub-panel\n' "$1"; }

ssl_marker_write() {
  local cert_dir="$1" panel="$2"
  install -d -m 0750 -o root -g root "$cert_dir"
  printf '%s\n' "$panel" >"$(ssl_marker_path "$cert_dir")"
  harden_file "$(ssl_marker_path "$cert_dir")" 0600
}

ssl_marker_panel() {
  local marker
  marker="$(ssl_marker_path "$1")"
  [[ -r "$marker" ]] && head -n 1 "$marker" || true
}

# Refuses to reuse a certificate directory that was created for another panel.
ssl_guard_cert_dir() {
  local cert_dir="$1" panel="$2" owner
  case "$cert_dir" in
  "${STATE_DIR}"/panels/*/ssl/*) ;;
  *)
    err "Refusing to use a certificate directory outside BaToHub state storage: $cert_dir"
    return 1
    ;;
  esac
  owner="$(ssl_marker_panel "$cert_dir")"
  if [[ -n "$owner" && "$owner" != "$panel" ]]; then
    err "Certificate directory ${cert_dir} belongs to panel ${owner}. BaToHub will not create a conflicting entry."
    return 1
  fi
  return 0
}

ssl_port80_readiness() {
  if port_in_use 80; then
    local holder
    holder="$(port_owner_hint 80 | tr '\n' ' ')"
    err "Port 80 is already in use. HTTP-01 validation needs port 80 free."
    err "Current listener: ${holder:-unknown}"
    err "Stop the service that owns port 80, or issue the certificate with DNS-01 outside BaToHub, then import it."
    return 1
  fi
  return 0
}

ssl_issue_cert() {
  local target="$1" cert_dir="$2" reload_cmd="$3" allow_ip="${4:-0}" email="${5:-}"
  local acme
  ssl_target_validate "$target" "$allow_ip" || return 1
  ssl_guard_cert_dir "$cert_dir" "${PANEL_NAME:-unknown}" || return 1
  acme="$(ssl_acme_path)" || {
    err "acme.sh is required to issue a certificate. Install it with: curl https://get.acme.sh | sh -s email=you@example.com"
    return 1
  }
  ssl_port80_readiness || return 1
  install -d -m 0750 -o root -g root "$cert_dir"
  if [[ -n "$email" ]]; then
    "$acme" --register-account -m "$email" >>"$LOG_FILE" 2>&1 || warn "ACME account registration returned a non-zero status; continuing."
  fi
  log "SSL issue requested for ${target} into ${cert_dir}"
  if ! "$acme" --issue -d "$target" --standalone --server letsencrypt >>"$LOG_FILE" 2>&1; then
    err "Certificate issuance failed for ${target}. Full output: ${LOG_FILE}"
    err "Common causes: DNS for ${target} does not point at this server, port 80 is filtered, or the ACME rate limit was reached."
    return 1
  fi
  if ! "$acme" --install-cert -d "$target" \
    --key-file "${cert_dir}/privkey.pem" \
    --fullchain-file "${cert_dir}/fullchain.pem" \
    --reloadcmd "$reload_cmd" >>"$LOG_FILE" 2>&1; then
    err "Certificate installation failed for ${target}. Full output: ${LOG_FILE}"
    return 1
  fi
  if [[ ! -s "${cert_dir}/fullchain.pem" || ! -s "${cert_dir}/privkey.pem" ]]; then
    err "acme.sh did not produce a complete certificate and private key pair for ${target}."
    return 1
  fi
  chmod 0644 "${cert_dir}/fullchain.pem"
  chmod 0600 "${cert_dir}/privkey.pem"
  chown root:root "${cert_dir}/fullchain.pem" "${cert_dir}/privkey.pem"
  ssl_marker_write "$cert_dir" "${PANEL_NAME:-unknown}"
  ok "Certificate issued for ${target}."
}

ssl_selfsigned_issue() {
  local target="$1" cert_dir="$2" days="${3:-365}" cn
  [[ -n "$target" ]] || {
    err "A domain name or address is required."
    return 1
  }
  ssl_guard_cert_dir "$cert_dir" "${PANEL_NAME:-unknown}" || return 1
  need_cmd openssl || {
    err "openssl is required to generate a self-signed certificate."
    return 1
  }
  cn="$target"
  install -d -m 0750 -o root -g root "$cert_dir"
  if ! openssl req -x509 -newkey rsa:2048 -nodes -days "$days" \
    -keyout "${cert_dir}/privkey.pem" -out "${cert_dir}/fullchain.pem" \
    -subj "/CN=${cn}" -addext "subjectAltName=DNS:${cn}" >>"$LOG_FILE" 2>&1; then
    err "Self-signed certificate generation failed. Full output: ${LOG_FILE}"
    return 1
  fi
  chmod 0644 "${cert_dir}/fullchain.pem"
  chmod 0600 "${cert_dir}/privkey.pem"
  chown root:root "${cert_dir}/fullchain.pem" "${cert_dir}/privkey.pem"
  ssl_marker_write "$cert_dir" "${PANEL_NAME:-unknown}"
  warn "A self-signed certificate is not trusted by clients. Use it for testing only."
}

ssl_status_pair() {
  local cert="$1" key="$2"
  if [[ ! -s "$cert" || ! -s "$key" ]]; then
    warn "No certificate pair is installed at ${cert}."
    return 1
  fi
  if ! need_cmd openssl; then
    warn "openssl is not installed; certificate details are unavailable."
    return 1
  fi
  local end_date end_epoch now_epoch days
  end_date="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- || true)"
  printf 'Certificate: %s\n' "$cert"
  printf 'Key: %s\n' "$key"
  openssl x509 -in "$cert" -noout -subject -issuer 2>/dev/null || true
  printf 'Expires: %s\n' "${end_date:-unknown}"
  if [[ -n "$end_date" ]]; then
    end_epoch="$(date -d "$end_date" +%s 2>/dev/null || printf '0')"
    now_epoch="$(date +%s)"
    if [[ "$end_epoch" -gt 0 ]]; then
      days=$(((end_epoch - now_epoch) / 86400))
      printf 'Days remaining: %s\n' "$days"
    fi
  fi
  return 0
}

ssl_days_remaining() {
  local cert="$1" end_date end_epoch now_epoch
  [[ -s "$cert" ]] || return 1
  end_date="$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- || true)"
  [[ -n "$end_date" ]] || return 1
  end_epoch="$(date -d "$end_date" +%s 2>/dev/null || printf '0')"
  now_epoch="$(date +%s)"
  printf '%s\n' "$(((end_epoch - now_epoch) / 86400))"
}

ssl_renew_cert() {
  local target="$1" acme
  acme="$(ssl_acme_path)" || {
    err "acme.sh is not installed; renewal cannot run."
    return 1
  }
  if [[ "$target" == self-signed* ]]; then
    warn "Self-signed certificates are not renewable through acme.sh."
    return 1
  fi
  log "SSL renewal requested for ${target}"
  if ! "$acme" --renew -d "$target" --force >>"$LOG_FILE" 2>&1; then
    err "Renewal failed for ${target}. Full output: ${LOG_FILE}"
    return 1
  fi
  ok "Renewal completed for ${target}."
}

ssl_renew_all_for_panel() {
  local acme
  acme="$(ssl_acme_path)" || {
    err "acme.sh is not installed; renewal cannot run."
    return 1
  }
  if [[ ! -d "${PANEL_SSL_DIR:-}" ]]; then
    warn "No BaToHub-managed certificate directory exists for panel ${PANEL_NAME:-unknown}."
    return 1
  fi
  local dir target count=0
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    [[ "$(ssl_marker_panel "$dir")" == "${PANEL_NAME:-}" ]] || continue
    target="$(basename "$dir")"
    if "$acme" --renew -d "$target" --force >>"$LOG_FILE" 2>&1; then
      ok "Renewed: ${target}"
    else
      err "Renewal failed: ${target}. Full output: ${LOG_FILE}"
    fi
    count=$((count + 1))
  done < <(find "${PANEL_SSL_DIR:-/nonexistent}" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
  if [[ "$count" -eq 0 ]]; then
    warn "No BaToHub-managed certificate was found for panel ${PANEL_NAME:-unknown}."
    return 1
  fi
  return 0
}

# Compares the DNS record of the target with the public address of this server
# and reports the usual mistakes instead of letting the ACME challenge fail with
# a generic error.
ssl_dns_check() {
  local target="$1" allow_ip="${2:-0}" resolved server
  if [[ "$allow_ip" == "1" ]] && valid_ipv4 "$target"; then
    return 0
  fi
  resolved="$(dns_lookup_ipv4 "$target")"
  if [[ -z "$resolved" ]]; then
    err "DNS lookup for ${target} returned no A record."
    err "Create the A record first, then run this operation again. Certificate validation cannot proceed without it."
    return 1
  fi
  server="$(server_public_ip)"
  printf 'DNS address for %s: %s\n' "$target" "$resolved"
  printf 'Public address of this server: %s\n' "$server"
  if [[ "$server" == "unknown" ]]; then
    warn "The public address of this server could not be determined; the DNS value cannot be compared."
    return 0
  fi
  local current
  current="$(ip -4 -brief address 2>/dev/null | awk '{print $3}' | cut -d/ -f1 | tr '\n' ' ' || true)"
  if [[ "$resolved" == "$server" || " $current " == *" $resolved "* ]]; then
    return 0
  fi
  warn "The DNS address for ${target} does not match this server."
  warn "Certificate authority validation will fail if the record still points elsewhere."
  if [[ "$INTERACTIVE" == 1 ]] && ui_confirm 'Continue anyway?'; then
    return 0
  fi
  err "Certificate issuance was not started."
  return 1
}

# Writes certificate paths into a panel configuration file, but only for keys
# the panel already declares. BaToHub never invents an option name: an unknown
# key would be a silent no-op, so the operator is told exactly what to configure
# instead.
ssl_register_env_keys() {
  local env_file="$1" cert="$2" key="$3"
  shift 3
  local candidate key_candidate updated=0
  [[ -f "$env_file" ]] || {
    err "Panel configuration file is missing: $env_file"
    return 1
  }
  for candidate in "$@"; do
    if grep -qE "^[[:space:]]*${candidate}=" "$env_file"; then
      panel_env_set "$env_file" "$candidate" "$cert" || return 1
      updated=1
    fi
    key_candidate="${candidate/CERT/KEY}"
    if [[ "$key_candidate" != "$candidate" ]] && grep -qE "^[[:space:]]*${key_candidate}=" "$env_file"; then
      panel_env_set "$env_file" "$key_candidate" "$key" || return 1
      updated=1
    fi
  done
  if [[ "$updated" -eq 1 ]]; then
    return 0
  fi
  ssl_print_manual_instructions "$cert" "$key" "$(basename "$(dirname "$cert")")"
  return 1
}

ssl_print_manual_instructions() {
  local cert="$1" key="$2" target="${3:-unknown}"
  warn "No existing certificate option was found in the panel configuration."
  printf 'Store these paths and point the panel at them through its own settings:\n'
  printf '  Certificate: %s\n' "$cert"
  printf '  Private key: %s\n' "$key"
  printf 'Copies of the paths are recorded in %s/panel-ssl.paths\n' "${PANEL_SSL_DIR:-$STATE_DIR}"
  install -d -m 0750 -o root -g root "${PANEL_SSL_DIR:-$STATE_DIR}"
  printf 'certificate=%s\nkey=%s\ndomain=%s\npanel=%s\n' "$cert" "$key" "$target" "${PANEL_NAME:-unknown}" >"${PANEL_SSL_DIR:-$STATE_DIR}/panel-ssl.paths"
  harden_file "${PANEL_SSL_DIR:-$STATE_DIR}/panel-ssl.paths" 0640
  return 0
}

ssl_remove_pair() {
  local cert_dir="$1"
  ssl_guard_cert_dir "$cert_dir" "${PANEL_NAME:-unknown}" || return 1
  rm -f -- "${cert_dir}/fullchain.pem" "${cert_dir}/privkey.pem" "$(ssl_marker_path "$cert_dir")"
  rmdir "$cert_dir" 2>/dev/null || true
  ok "Managed certificate files removed from ${cert_dir}."
}
