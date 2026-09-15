#!/usr/bin/env bash
set -Eeuo pipefail

# Shared helper library. Every executable sources this file first.

export APP_NAME="BaToHub"

# Values supplied through the environment take precedence over the configuration
# file. The configured values are captured here, the file is read, and the
# environment wins for every key it defines.
ENV_INSTALL_DIR="${INSTALL_DIR:-}"
ENV_CONFIG_DIR="${CONFIG_DIR:-}"
ENV_STATE_DIR="${STATE_DIR:-}"
ENV_LOG_DIR="${LOG_DIR:-}"
ENV_BACKUP_DIR="${BACKUP_DIR:-}"
ENV_BACKUP_KEEP="${BACKUP_KEEP:-}"
ENV_GLOBAL_CMD="${GLOBAL_CMD_NAME:-}"

BATOHUB_ROOT="${BATOHUB_ROOT:-/opt/batohub}"
INSTALL_DIR="${ENV_INSTALL_DIR:-$BATOHUB_ROOT}"
CONFIG_DIR="${ENV_CONFIG_DIR:-/etc/batohub}"
STATE_DIR="${ENV_STATE_DIR:-/var/lib/batohub}"
LOG_DIR="${ENV_LOG_DIR:-/var/log/batohub}"
CONFIG_FILE="${CONFIG_DIR}/batohub.conf"

export INSTALL_DIR CONFIG_DIR STATE_DIR LOG_DIR CONFIG_FILE

if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

INSTALL_DIR="${ENV_INSTALL_DIR:-$INSTALL_DIR}"
CONFIG_DIR="${ENV_CONFIG_DIR:-$CONFIG_DIR}"
STATE_DIR="${ENV_STATE_DIR:-$STATE_DIR}"
LOG_DIR="${ENV_LOG_DIR:-$LOG_DIR}"
# The backup directory follows an overridden state directory: the packaged
# default is only kept when the state directory is also the packaged default.
if [[ -z "$ENV_BACKUP_DIR" && "${BACKUP_DIR:-}" == "/var/lib/batohub/backups" && "$STATE_DIR" != "/var/lib/batohub" ]]; then
  BACKUP_DIR=""
fi
BACKUP_DIR="${ENV_BACKUP_DIR:-${BACKUP_DIR:-$STATE_DIR/backups}}"
BACKUP_KEEP="${ENV_BACKUP_KEEP:-${BACKUP_KEEP:-5}}"
GLOBAL_CMD_NAME="${ENV_GLOBAL_CMD:-${GLOBAL_CMD_NAME:-/usr/local/bin/BaToHub}}"
GITHUB_REPO="${GITHUB_REPO:-isAsli/BaTo-Hub}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

CONFIG_FILE="${CONFIG_DIR}/batohub.conf"
LOG_FILE="${LOG_DIR}/batohub.log"
LOCK_DIR="${STATE_DIR}/locks"
PANEL_CONF="${CONFIG_DIR}/panel.conf"

# A configuration file may point at the packaged installation path. When that
# path does not exist the tree this file was loaded from is used instead, so a
# checkout and a packaged installation both work.
if [[ ! -r "${INSTALL_DIR}/VERSION" && -r "${BATOHUB_ROOT}/VERSION" ]]; then
  INSTALL_DIR="$BATOHUB_ROOT"
fi

export PANEL_DIR="${INSTALL_DIR}/panels"
export TOOL_DIR="${INSTALL_DIR}/tools"

APP_VERSION="unknown"
if [[ -r "${INSTALL_DIR}/VERSION" ]]; then
  APP_VERSION="$(head -n 1 "${INSTALL_DIR}/VERSION" | tr -d '[:space:]')"
fi

# Non-interactive shells (CI, containers) must never block on a prompt.
INTERACTIVE=0
[[ -t 0 && -t 1 ]] && INTERACTIVE=1

# These names form the interface between the library, the core scripts and the
# panel and tool modules, so they are exported.
export BATOHUB_ROOT INSTALL_DIR CONFIG_DIR STATE_DIR LOG_DIR LOG_FILE
# shellcheck disable=SC2155
export APP_NAME APP_VERSION PANEL_DIR TOOL_DIR PANEL_CONF CONFIG_FILE
export BACKUP_DIR BACKUP_KEEP GITHUB_REPO GITHUB_BRANCH INTERACTIVE LOCK_DIR

ensure_runtime_dirs() {
  local dir
  for dir in "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$LOCK_DIR" "$BACKUP_DIR"; do
    [[ -d "$dir" ]] && continue
    install -d -m 0750 -o root -g root "$dir" 2>/dev/null || mkdir -p "$dir"
  done
  if [[ ! -f "$LOG_FILE" ]]; then
    install -m 0640 -o root -g root /dev/null "$LOG_FILE" 2>/dev/null || : >"$LOG_FILE"
  fi
}

log() {
  ensure_runtime_dirs >/dev/null 2>&1 || true
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

info() { printf '%s\n' "$*"; }
ok() {
  printf 'OK: %s\n' "$*"
  log "OK $*"
}
warn() {
  printf 'WARNING: %s\n' "$*" >&2
  log "WARN $*"
}
err() {
  printf 'ERROR: %s\n' "$*" >&2
  log "ERROR $*"
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    err "Root privileges are required for this operation."
    return 1
  fi
  return 0
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

need_cmds() {
  local name missing=0
  for name in "$@"; do
    if ! need_cmd "$name"; then
      err "Missing required command: $name"
      missing=1
    fi
  done
  return "$missing"
}

mktemp_file() {
  local template="${1:-task}"
  mktemp "${TMPDIR:-/tmp}/batohub.${template}.XXXXXX"
}

mktemp_dir() {
  local template="${1:-task}"
  mktemp -d "${TMPDIR:-/tmp}/batohub.${template}.XXXXXX"
}

with_lock() {
  local lock_name="$1"
  shift
  local lock_file="${LOCK_DIR}/${lock_name}.lock" fd status=0
  ensure_runtime_dirs >/dev/null 2>&1 || true
  if ! need_cmd flock; then
    "$@"
    return $?
  fi
  exec {fd}>"$lock_file" || return 1
  flock -x "$fd" || return 1
  set +e
  "$@"
  status=$?
  set -e
  flock -u "$fd" 2>/dev/null || true
  exec {fd}>&-
  return "$status"
}

# Writes file content atomically: a temporary file in the destination directory
# is fully written, permissioned and then renamed over the target.
atomic_write() {
  local target="$1" mode="$2" content="$3" parent tmp
  parent="$(dirname "$target")"
  [[ -d "$parent" ]] || install -d -m 0750 -o root -g root "$parent"
  tmp="$(mktemp "${parent}/.batohub.XXXXXX")"
  chmod 0600 "$tmp"
  printf '%s' "$content" >"$tmp"
  chmod "$mode" "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$target"
  chmod "$mode" "$target"
  chown root:root "$target" 2>/dev/null || true
}

harden_file() {
  local path="$1" mode="${2:-0600}"
  [[ -e "$path" ]] || return 0
  chmod "$mode" "$path" 2>/dev/null || true
  chown root:root "$path" 2>/dev/null || true
}

harden_dir() {
  local path="$1" mode="${2:-0750}"
  [[ -d "$path" ]] || return 0
  chmod "$mode" "$path" 2>/dev/null || true
  chown root:root "$path" 2>/dev/null || true
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

valid_panel_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
valid_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
valid_env_key() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }

port_in_use() {
  local port="$1"
  [[ -n "$port" ]] || return 1
  if need_cmd ss; then
    ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
  elif need_cmd lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1
  fi
}

port_owner_hint() {
  local port="$1"
  if need_cmd ss; then
    ss -lntp "sport = :${port}" 2>/dev/null | tail -n +2 | awk '{print $NF}' | head -n 3
  fi
}

json_get() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 1
  python3 - "$file" "$key" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding='utf-8') as handle:
        value = json.load(handle)
    for part in sys.argv[2].split('.'):
        value = value.get(part) if isinstance(value, dict) else None
    if value is None:
        print("")
    elif isinstance(value, (dict, list)):
        print(json.dumps(value, separators=(',', ':')))
    elif isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
except (OSError, ValueError, TypeError):
    raise SystemExit(1)
PY
}

json_list() {
  local file="$1" key="$2"
  json_get "$file" "$key" | python3 -c '
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
try:
    value = json.loads(raw)
except ValueError:
    raise SystemExit(1)
if isinstance(value, list):
    for item in value:
        print(item if isinstance(item, str) else json.dumps(item))
elif isinstance(value, str):
    print(value)
'
}

read_env_value() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 1
  valid_env_key "$key" || return 1
  grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true
}

set_env_value() {
  local file="$1" key="$2" value="$3" tmp
  valid_env_key "$key" || {
    err "Invalid environment key: $key"
    return 1
  }
  [[ -f "$file" ]] || {
    err "Configuration file does not exist: $file"
    return 1
  }
  local mode
  # The original mode is preserved so a 0600 state file is never widened.
  mode="$(stat -c '%a' "$file" 2>/dev/null || printf '640')"
  tmp="$(mktemp_file env)"
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    $0 ~ "^[[:space:]]*" key "=" { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" >"$tmp"
  chmod 0600 "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$file"
  harden_file "$file" "$mode"
}

config_get() {
  local key="$1"
  read_env_value "$CONFIG_FILE" "$key"
}

state_read() {
  local key="$1"
  read_env_value "$PANEL_CONF" "$key"
}

state_write() {
  local key="$1" value="$2"
  [[ -f "$PANEL_CONF" ]] || atomic_write "$PANEL_CONF" 0600 ""
  with_lock state set_env_value "$PANEL_CONF" "$key" "$value"
}

server_public_ip() {
  local ip=""
  if need_cmd curl; then
    ip="$(curl -fsS --max-time 8 --proto '=https' --tlsv1.2 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]] && need_cmd ip; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") { print $(i+1); exit }}')"
  fi
  printf '%s\n' "${ip:-unknown}"
}

dns_lookup_ipv4() {
  local host="$1" ip=""
  if need_cmd getent; then
    ip="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | head -n 1 || true)"
  fi
  if [[ -z "$ip" ]] && need_cmd dig; then
    ip="$(dig +short A "$host" 2>/dev/null | grep -E '^[0-9.]+$' | head -n 1 || true)"
  fi
  if [[ -z "$ip" ]] && need_cmd host; then
    ip="$(host -t A "$host" 2>/dev/null | awk '/has address/ {print $NF}' | head -n 1 || true)"
  fi
  printf '%s\n' "${ip:-}"
}

os_id() {
  local id="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    id="$(. /etc/os-release && printf '%s' "${ID:-unknown}")"
  fi
  printf '%s\n' "$id"
}

os_pretty_name() {
  local name="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
  fi
  printf '%s\n' "$name"
}

os_version_id() {
  local version="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")"
  fi
  printf '%s\n' "$version"
}

systemd_available() {
  need_cmd systemctl && [[ -d /run/systemd/system ]]
}

service_registered() {
  local service="$1"
  [[ -n "$service" ]] || return 1
  systemd_available || return 1
  systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${service}\.service"
}

service_active() {
  local service="$1"
  service_registered "$service" || return 1
  systemctl is-active --quiet "$service" 2>/dev/null
}

run_logged() {
  local label="$1"
  shift
  log "RUN ${label}: $*"
  if "$@" >>"$LOG_FILE" 2>&1; then
    log "RUN_OK ${label}"
    return 0
  fi
  log "RUN_FAIL ${label}"
  return 1
}

ui_clear() {
  if [[ "$INTERACTIVE" == 1 ]]; then
    clear 2>/dev/null || true
  fi
}

ui_title() {
  ui_clear
  printf '%s\n' "BaToHub ${APP_VERSION}"
  printf '%s\n' "$1"
  printf '%s\n' '----------------------------------------'
}

ui_prompt() {
  local prompt="$1" fallback="${2:-}" value=""
  if [[ "$INTERACTIVE" != 1 ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  read -r -p "$prompt" value || value="$fallback"
  printf '%s\n' "$value"
}

ui_menu_choice() {
  local prompt="${1:-Selection: }" value=""
  if [[ "$INTERACTIVE" != 1 ]]; then
    printf '%s\n' ""
    return 1
  fi
  read -r -p "$prompt" value || value=""
  printf '%s\n' "$value"
}

ui_confirm() {
  local prompt="$1" answer=""
  if [[ "$INTERACTIVE" != 1 ]]; then
    return 1
  fi
  read -r -p "${prompt} [y/N] " answer || answer=""
  [[ "$answer" =~ ^[Yy]$ ]]
}

ui_confirm_phrase() {
  local phrase="$1" prompt="$2" answer=""
  if [[ "$INTERACTIVE" != 1 ]]; then
    return 1
  fi
  read -r -p "${prompt} Type ${phrase} to confirm: " answer || answer=""
  [[ "$answer" == "$phrase" ]]
}

pause() {
  if [[ "$INTERACTIVE" != 1 ]]; then
    return 0
  fi
  read -r -p 'Press Enter to continue... ' _ || true
}

show_logs() {
  ensure_runtime_dirs >/dev/null 2>&1 || true
  if [[ -r "$LOG_FILE" ]]; then
    tail -n 80 "$LOG_FILE"
  else
    warn "Log file is not available: $LOG_FILE"
  fi
}

current_timestamp() { date -u +%Y%m%dT%H%M%SZ; }
