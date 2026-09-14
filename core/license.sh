#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

LICENSE_FILE="${CONFIG_DIR}/license.json"
LICENSE_KEY_FILE="${CONFIG_DIR}/.license_key"

fingerprint() {
  local m h
  m=$(cat /etc/machine-id 2>/dev/null || true)
  h=$(hostname 2>/dev/null || true)
  printf '%s|%s|%s' "$m" "$h" "$APP_NAME" | sha256sum | awk '{print $1}'
}

license_prompt() {
  printf '\n%s\n' "OpenLicense API Key"
  local key
  read -r -p '> ' key
  key=$(printf '%s' "$key" | sed 's/[[:space:]]//g')
  if [ -z "$key" ]; then
    err 'License key is empty.'
    return 1
  fi
  validate_license "$key" || return 1
}

validate_license() {
  local key="$1" fp payload tmp cafile code valid error
  fp=$(fingerprint)

  cafile="/etc/ssl/certs/ca-certificates.crt"
  if [ ! -f "$cafile" ]; then
    cafile=""
  fi

  payload=$(python3 - "$key" "$LICENSE_PRODUCT" "$fp" "$APP_VERSION" <<'PY'
import json
import socket
import sys

print(json.dumps({
    "key": sys.argv[1],
    "product": sys.argv[2],
    "fingerprint": sys.argv[3],
    "hostname": socket.gethostname(),
    "version": sys.argv[4],
}))
PY
  )

  tmp=$(mktemp_file "license")

  local curl_opts=(
    -sS
    -o "$tmp"
    -w '%{http_code}'
    --connect-timeout 8
    --max-time 20
    -H 'Content-Type: application/json'
    -d "$payload"
  )
  if [ -n "$cafile" ]; then
    curl_opts+=(--cacert "$cafile")
  fi

  code=$(curl "${curl_opts[@]}" "$LICENSE_API" 2>>"$LOG_FILE" || true)

  if [ -z "$code" ] || [ "$code" = "000" ]; then
    rm -f "$tmp"
    err "License server unreachable: $LICENSE_API"
    return 1
  fi

  valid=$(json_get "$tmp" "valid")
  error=$(json_get "$tmp" "error")

  if [ "$valid" != "True" ] && [ "$valid" != "true" ]; then
    rm -f "$tmp"
    if [ -z "$error" ]; then
      error='license_rejected'
    fi
    err "License rejected: $error"
    printf '%s\n' "Contact $SUPPORT for a valid license."
    return 1
  fi

  install -m 600 "$tmp" "$LICENSE_FILE"
  rm -f "$tmp"

  printf '%s\n' "$key" | install -m 600 /dev/stdin "$LICENSE_KEY_FILE"

  ok 'License verified'
  return 0
}

ensure_license() {
  if [ -s "$LICENSE_KEY_FILE" ] && [ -s "$LICENSE_FILE" ]; then
    local key
    key=$(cat "$LICENSE_KEY_FILE" | sed 's/[[:space:]]//g')
    if validate_license "$key" >/dev/null 2>&1; then
      return 0
    fi
  fi

  while ! license_prompt; do
    :
  done
}
