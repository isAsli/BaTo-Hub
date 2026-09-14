#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

PANEL_DIR="${INSTALL_DIR}/panels"
PANEL_NAME="rebecca"
REBECCA_DIR="${REBECCA_DIR:-/opt/rebecca}"
REBECCA_SSL_CERT_DIR="${REBECCA_DIR}/certs"
RENEWAL_HOOK="/etc/letsencrypt/renewal-hooks/deploy/batohub-rebecca.sh"

ssl_menu() {
  while :; do
    clear
    banner "Rebecca / SSL"
    printf '%s\n' '1) Obtain and install SSL'
    printf '%s\n' '2) Renew SSL'
    printf '%s\n' '3) SSL status'
    printf '%s\n' '4) Remove SSL settings'
    printf '%s\n' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1) ssl_install;;
      2) ssl_renew;;
      3) ssl_status;;
      4) ssl_remove;;
      0) return;;
    esac
  done
}

ssl_install() {
  clear
  banner "Rebecca / SSL / Install"
  if [ ! -d "$REBECCA_DIR" ]; then
    err 'Rebecca installation was not detected at /opt/rebecca.'
    pause
    return
  fi

  local domain email ip dip certdir
  read -r -p 'Panel domain: ' domain
  read -r -p 'Certbot email: ' email

  domain=$(printf '%s' "$domain" | sed 's/[[:space:]]//g')
  if [ -z "$domain" ] || ! [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; then
    err 'Invalid domain.'
    pause
    return
  fi

  if [ -z "$email" ]; then
    err 'Email is required.'
    pause
    return
  fi

  ip=$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
  dip=$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1{print $1}')

  if [ -z "$dip" ]; then
    err 'DNS does not resolve for the domain.'
    pause
    return
  fi

  if [ -n "$ip" ] && [ "$ip" != "$dip" ]; then
    err "DNS mismatch: domain=$dip server=$ip"
    pause
    return
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    info 'Certbot is not installed. Attempting installation.'
    if ! apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot; then
      err 'Certbot installation failed.'
      pause
      return
    fi
  fi

  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)80$'; then
    err 'Port 80 is occupied. Stop the HTTP service or use a webroot challenge before retrying.'
    pause
    return
  fi

  certdir="$REBECCA_SSL_CERT_DIR/$domain"
  install -d -m 750 "$certdir"
  chown -R root:root "$REBECCA_SSL_CERT_DIR"

  install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy

  cat > "$RENEWAL_HOOK" <<'HOOK'
#!/usr/bin/env bash
set -e
domain="${RENEWED_DOMAINS%% *}"
certdir="/opt/rebecca/certs/$domain"
install -d -m 750 "$certdir"
install -m 640 "/etc/letsencrypt/live/batohub-$domain/fullchain.pem" "$certdir/fullchain.pem"
install -m 600 "/etc/letsencrypt/live/batohub-$domain/privkey.pem" "$certdir/privkey.pem"
chown root:root "$certdir"/*
systemctl restart rebecca >/dev/null 2>&1 || true
HOOK
  chmod 700 "$RENEWAL_HOOK"

  if ! certbot certonly --standalone --non-interactive --agree-tos \
    --email "$email" --cert-name "batohub-$domain" -d "$domain" 2>&1 | tee -a "$LOG_FILE"; then
    err 'Certbot failed.'
    show_last_logs
    pause
    return
  fi

  install -m 640 "/etc/letsencrypt/live/batohub-$domain/fullchain.pem" "$certdir/fullchain.pem" || {
    err 'Certificate copy failed.'
    pause
    return
  }
  install -m 600 "/etc/letsencrypt/live/batohub-$domain/privkey.pem" "$certdir/privkey.pem" || {
    err 'Private key copy failed.'
    pause
    return
  }
  chown root:root "$certdir"/*

  set_env REBECCA_CERT_BASE "$REBECCA_SSL_CERT_DIR"
  set_env UVICORN_SSL_CERTFILE "$certdir/fullchain.pem"
  set_env UVICORN_SSL_KEYFILE "$certdir/privkey.pem"
  set_env UVICORN_SSL_CA_TYPE public

  systemctl daemon-reload 2>>"$LOG_FILE" || true
  systemctl restart rebecca 2>>"$LOG_FILE" || true

  ok "Certificate saved to $certdir"
  ok 'Rebecca SSL environment updated'
  ok 'Renewal is managed by Certbot'
  pause
}

ssl_renew() {
  clear
  banner 'Rebecca / SSL / Renew'
  if certbot renew --quiet; then
    ok 'Renewal check completed'
  else
    err 'Renewal failed'
    show_last_logs
  fi
  pause
}

ssl_status() {
  clear
  banner 'Rebecca / SSL / Status'
  certbot certificates 2>&1 | sed -n '/Certificate Name/,$p'
  pause
}

ssl_remove() {
  clear
  banner 'Rebecca / SSL / Remove'
  local x
  read -r -p 'To remove SSL settings, type REMOVE: ' x
  if [ "${x:-}" != "REMOVE" ]; then
    return
  fi
  set_env UVICORN_SSL_CERTFILE ''
  set_env UVICORN_SSL_KEYFILE ''
  systemctl restart rebecca 2>>"$LOG_FILE" || true
  ok 'Rebecca SSL settings cleared'
  pause
}

set_env() {
  local k="$1" v="$2" f fd
  f="$REBECCA_DIR/.env"
  if [ ! -f "$f" ]; then
    err 'Rebecca .env not found.'
    return 1
  fi
  fd=$(lock_acquire "$REBECCA_DIR/.env.lock")
  if grep -qE "^${k}=" "$f"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$f"
  else
    printf '\n%s=%s\n' "$k" "$v" >> "$f"
  fi
  chmod 640 "$f" 2>/dev/null || true
  lock_release "$fd"
}
