#!/usr/bin/env bash
set -u
CFG=/etc/batohub/batohub.conf
[ -f "$CFG" ] && . "$CFG"
APP_VERSION="$(cat /opt/batohub/VERSION 2>/dev/null || printf "%s" "${APP_VERSION:-0.0.1}")"
LOG_FILE="${LOG_DIR:-/var/log/batohub}/batohub.log"
mkdir -p "${LOG_DIR:-/var/log/batohub}" 2>/dev/null || true
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
red(){ printf '\033[31m%s\033[0m' "$*"; }
green(){ printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
cyan(){ printf '\033[36m%s\033[0m' "$*"; }
white(){ printf '\033[97m%s\033[0m' "$*"; }
hr(){ printf '\033[90m────────────────────────────────────────────────────────────\033[0m\n'; }
err(){ log "ERROR $*"; printf '\033[31m✗ %s\033[0m\n' "$*"; }
show_error(){ printf '\033[31m%s\033[0m\n' '---'; tail -25 "$LOG_FILE" 2>/dev/null || true; printf '\033[31m%s\033[0m\n' '---'; }
ok(){ log "OK $*"; printf '\033[32m✓ %s\033[0m\n' "$*"; }
run(){ log "RUN $*"; "$@" 2>>"$LOG_FILE"; }
need_root(){ [ "$(id -u)" -eq 0 ] || { err "Root privileges are required."; exit 1; }; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; return 1; }; }
json_get(){ python3 - "$1" "$2" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1])); v=d
 for p in sys.argv[2].split('.'):
  v=v[p]
 print(v if v is not None else '')
except Exception: print('')
PY
}
