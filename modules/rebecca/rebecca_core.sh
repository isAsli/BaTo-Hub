#!/usr/bin/env bash
. /opt/batohub/lib/common.sh

rebecca_dir(){ printf '%s' "${REBECCA_DIR:-/opt/rebecca}"; }

rebecca_is_installed(){
  local d
  d=$(rebecca_dir)
  [ -d "$d" ] && [ -f "$d/.env" ] && [ -f "$d/Rebecca" ]
}

rebecca_service_name(){
  if systemctl list-unit-files 2>/dev/null | grep -qE '^rebecca\\.service$'; then
    printf 'rebecca'
  else
    printf 'rebecca'
  fi
}

rebecca_status_text(){
  local svc
  svc=$(rebecca_service_name)
  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'systemctl is not available; cannot query service state.\n'
    return 1
  fi
  systemctl is-active "$svc" >/dev/null 2>&1 && printf 'active' || printf 'inactive/unavailable'
}

rebecca_binary_exists(){
  local d
  d=$(rebecca_dir)
  [ -x "$d/Rebecca" ] || [ -x "$d/rebecca" ]
}

rebecca_port_info(){
  local d
  d=$(rebecca_dir)
  [ -f "$d/.env" ] || return 1
  local host port
  host=$(grep -E '^UVICORN_HOST=' "$d/.env" | sed 's/^UVICORN_HOST=//' | tr -d '"\' | head -n 1)
  port=$(grep -E '^UVICORN_PORT=' "$d/.env" | sed 's/^UVICORN_PORT=//' | tr -d '"\' | head -n 1)
  printf '%s\n' "${host:-0.0.0.0} ${port:-8080}"
}
