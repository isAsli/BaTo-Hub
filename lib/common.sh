#!/usr/bin/env bash
set -euo pipefail

CFG="${CONFIG_DIR:-/etc/batohub}/batohub.conf"
[ -f "$CFG" ] && . "$CFG"

APP_VERSION="${APP_VERSION:-0.0.2}"
if [ -f "${INSTALL_DIR:-/opt/batohub}/VERSION" ]; then
  APP_VERSION="$(cat "${INSTALL_DIR:-/opt/batohub}/VERSION" | sed -n '1p' | tr -d '[:space:]')"
fi

LOG_DIR="${LOG_DIR:-/var/log/batohub}"
LOG_FILE="${LOG_DIR}/batohub.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
  printf '%s\n' "$*" >&2
}

warn() {
  printf '%s\n' "$*" >&2
}

err() {
  log "ERROR $*"
  printf '%s\n' "ERROR: $*" >&2
}

show_last_logs() {
  if [ -f "$LOG_FILE" ]; then
    printf '%s\n' "---"
    tail -n 25 "$LOG_FILE" 2>/dev/null || true
    printf '%s\n' "---"
  fi
}

ok() {
  log "OK $*"
  printf '%s\n' "OK: $*" >&2
}

run_cmd() {
  log "RUN $*"
  if "$@"; then
    log "RUN_OK $*"
  else
    log "RUN_FAIL $*"
    return 1
  fi
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Root privileges are required."
    exit 1
  fi
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing command: $1"
    return 1
  fi
}

need_cmds() {
  local missing=0
  for c in "$@"; do
    if ! need_cmd "$c"; then
      missing=1
    fi
  done
  return "$missing"
}

mktemp_file() {
  local suffix="${1:-}"
  if [ -n "$suffix" ]; then
    mktemp "/tmp/batohub.${suffix}.XXXXXX"
  else
    mktemp "/tmp/batohub.XXXXXX"
  fi
}

mktemp_dir() {
  mktemp -d "/tmp/batohub.XXXXXX"
}

lock_acquire() {
  local lockfile="$1"
  local fd="${2:-200}"
  mkdir -p "$(dirname "$lockfile")" 2>/dev/null || true
  exec {fd}>"$lockfile"
  flock -x "$fd"
  printf '%s\n' "$fd"
}

lock_release() {
  local fd="${1:-200}"
  exec {fd}>&-
}

json_get() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

path = sys.argv[2]
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    value = data
    for key in path.split("."):
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            value = ""
            break
    if value is None:
        value = ""
    print(value)
except Exception:
    print("")
PY
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

sanitize_shell_text() {
  local value="$1"
  if [ -z "$value" ]; then
    printf ''
    return
  fi
  printf '%s' "$value" | tr -d '[:cntrl:]'
}

write_protected_file() {
  local target="$1"
  local content="$2"
  local tmp
  tmp=$(mktemp_file "protected")
  printf '%s\n' "$content" > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  chown root:root "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$target"
  chmod 600 "$target" 2>/dev/null || true
  chown root:root "$target" 2>/dev/null || true
}

read_protected_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cat "$file"
  fi
}
