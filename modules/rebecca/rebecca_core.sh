#!/usr/bin/env bash
set -euo pipefail

rebecca_dir() {
  printf '%s' "${REBECCA_DIR:-/opt/rebecca}"
}

rebecca_is_installed() {
  local d
  d=$(rebecca_dir)
  [ -d "$d" ] && [ -f "$d/.env" ] && [ -f "$d/Rebecca" ]
}

rebecca_service_name() {
  printf '%s' 'rebecca'
}

rebecca_status_text() {
  local svc
  svc=$(rebecca_service_name)
  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'systemctl is not available; cannot query service state.\n'
    return 1
  fi
  if systemctl is-active "$svc" >/dev/null 2>&1; then
    printf 'active'
  else
    printf 'inactive/unavailable'
  fi
}

rebecca_binary_exists() {
  local d exe
  d=$(rebecca_dir)
  for exe in "$d/Rebecca" "$d/rebecca"; do
    if [ -x "$exe" ]; then
      return 0
    fi
  done
  return 1
}

rebecca_port_info() {
  local d host port
  d=$(rebecca_dir)
  if [ ! -f "$d/.env" ]; then
    return 1
  fi
  host=$(grep -E '^UVICORN_HOST=' "$d/.env" 2>/dev/null | sed 's/^UVICORN_HOST=//' | tr -d '"\' | sed 's/[[:space:]]//g' | head -n 1 || true)
  port=$(grep -E '^UVICORN_PORT=' "$d/.env" 2>/dev/null | sed 's/^UVICORN_PORT=//' | tr -d '"\' | sed 's/[[:space:]]//g' | head -n 1 || true)
  printf '%s\n' "${host:-0.0.0.0} ${port:-8080}"
}
