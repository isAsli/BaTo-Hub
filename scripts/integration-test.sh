#!/usr/bin/env bash
set -Eeuo pipefail

# Integration verification against local service endpoints.
#
# The suite installs BaToHub into a disposable prefix, starts local HTTP services
# that implement the endpoints the shipped code talks to (the node and user
# endpoints each panel declares in its own panel.json, and the Bot API methods the
# backup delivery and the management bot use), and then drives the documented
# commands against them. Authentication, request bodies, response parsing, error
# handling and the state BaToHub keeps on disk are all exercised end to end; the
# services never modify anything outside the work directory.
#
# Usage: bash scripts/integration-test.sh [work-directory]
#
# The panels themselves are not installed here: a panel install needs a container
# or a machine of its own with its package manager, a service manager and open
# ports, which this environment does not provide. What is verified is the BaToHub
# side of every call, against the contract each panel publishes.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-/tmp/batohub-integration}"
PREFIX="${WORK}/opt"
ETC_DIR="${WORK}/etc"
STATE="${WORK}/state"
LOGS="${WORK}/logs"
STUB_DIR="${WORK}/stub"
COMMAND="${WORK}/bin/BaToHub"
TOKEN="100200300:integration-token"

PASS=0
FAIL=0

step() { printf '\n-- %s\n' "$1"; }
ok() {
  printf 'ok   %s\n' "$1"
  PASS=$((PASS + 1))
}
no() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=$((FAIL + 1))
}

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$description"
  else
    no "$description"
  fi
}

expect_output() {
  local description="$1" needle="$2"
  shift 2
  local output
  output="$("$@" 2>&1 || true)"
  if [[ "$output" == *"$needle"* ]]; then
    ok "$description"
  else
    no "$description"
    printf '     expected to find: %s\n' "$needle" >&2
    printf '     actual output: %s\n' "$output" >&2
  fi
}

export BATOHUB_SOURCE_DIR="$ROOT"
export INSTALL_DIR="$PREFIX"
export CONFIG_DIR="$ETC_DIR"
export STATE_DIR="$STATE"
export LOG_DIR="$LOGS"
export BACKUP_DIR="${STATE}/backups"
export GLOBAL_CMD_NAME="$COMMAND"

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

PANEL_PORT="$(free_port)"
TELEGRAM_PORT="$(free_port)"
export TELEGRAM_API_BASE="http://127.0.0.1:${TELEGRAM_PORT}"

# hub runs one documented command with the environment the suite configured.
hub() { "$COMMAND" "$@"; }
# Wrappers for the commands that run with one value changed, so an option that
# selects an account or a search path can be passed to the command itself.
hub_wrong_token() { NODES_API_TOKEN_MARZBAN=wrong-token hub "$@"; }
hub_as_viewer() { BATOHUB_ADMIN=viewer hub "$@"; }
hub_with_docker() { PATH="${WORK}/fakebin:$PATH" hub "$@"; }

PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT

start_stub() {
  local mode="$1" port="$2"
  python3 "${ROOT}/scripts/integration-stub.py" "$mode" "$port" "$STUB_DIR" "$ROOT" \
    >"${WORK}/stub-${mode}.out" 2>"${WORK}/stub-${mode}.err" &
  PIDS+=("$!")
  local waited=0
  while [[ "$waited" -lt 50 ]]; do
    if grep -q ready "${WORK}/stub-${mode}.out" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  printf 'the %s stub did not start:\n' "$mode" >&2
  cat "${WORK}/stub-${mode}.err" >&2
  return 1
}

rm -rf "$WORK"
mkdir -p "$WORK" "$STUB_DIR"

step "installer"
if bash "$ROOT/install.sh" >"$WORK/install.log" 2>&1; then
  ok "installer completed"
else
  no "installer completed"
  tail -n 40 "$WORK/install.log" >&2
fi

# The service doubles and the credentials BaToHub is configured with. Every panel
# points at the same endpoint under its own path prefix, so a request identifies
# the panel it was made for.
python3 - "$STUB_DIR/accounts.json" "$PANEL_PORT" "$TOKEN" <<'PY'
import json
import sys

path, port, token = sys.argv[1], sys.argv[2], sys.argv[3]
nodes = [{"id": 1, "name": "existing-1", "address": "10.0.0.10", "port": 62050, "status": "connected"}]
users = [
    {"username": "user-a", "status": "active", "expire": 1900000000, "data_limit": 10737418240, "used_traffic": 1073741824},
    {"username": "user-b", "status": "active", "expire": 1900000000, "data_limit": 21474836480, "used_traffic": 5368709120},
    {"username": "user-c", "status": "expired", "expire": 1700000000, "data_limit": 0, "used_traffic": 99},
]
inbounds = [
    {"id": 1, "remark": "inbound-a", "protocol": "vless", "port": 443, "settings": "{}", "streamSettings": "{}"},
    {"id": 2, "remark": "inbound-b", "protocol": "vmess", "port": 8443, "settings": "{}", "streamSettings": "{}"},
]
accounts = {"bot_token": token}
for panel in ("rebecca", "marzban", "pasarguard", "3x-ui", "vpn-ui"):
    mode = "inbounds" if panel in ("3x-ui", "vpn-ui") else "users"
    accounts[panel] = {
        "auth": "login-cookie" if panel in ("3x-ui", "vpn-ui") else ("bearer" if panel == "rebecca" else "login"),
        "user": "stubuser",
        "password": "stubpass",
        "token": f"token-{panel}",
        "cookie": f"session-{panel}",
        "nodes": [dict(item) for item in nodes],
        "users": [dict(item) for item in (inbounds if mode == "inbounds" else users)],
    }
accounts["updates"] = [
    {"update_id": 11, "message": {"message_id": 11, "from": {"id": 1001}, "chat": {"id": 555000111, "type": "private"}, "text": "/help"}},
    {"update_id": 12, "message": {"message_id": 12, "from": {"id": 1001}, "chat": {"id": 555000111, "type": "private"}, "text": "/status"}},
    {"update_id": 13, "message": {"message_id": 13, "from": {"id": 1001}, "chat": {"id": 555000111, "type": "private"}, "text": "/panels"}},
    {"update_id": 14, "message": {"message_id": 14, "from": {"id": 1001}, "chat": {"id": 555000111, "type": "private"}, "text": "/users"}},
    {"update_id": 15, "message": {"message_id": 15, "from": {"id": 1002}, "chat": {"id": 555000112, "type": "private"}, "text": "/restart"}},
    {"update_id": 16, "message": {"message_id": 16, "from": {"id": 9999}, "chat": {"id": 555000999, "type": "private"}, "text": "/backup"}},
]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(accounts, handle, indent=2)
PY

# nodes.conf carries the endpoint and credentials of every panel.
{
  for panel in rebecca marzban pasarguard 3x-ui vpn-ui; do
    upper="$(printf '%s' "$panel" | tr '[:lower:]-' '[:upper:]_')"
    printf 'NODES_API_BASE_%s="http://127.0.0.1:%s/%s"\n' "$upper" "$PANEL_PORT" "$panel"
    printf 'NODES_API_TOKEN_%s="token-%s"\n' "$upper" "$panel"
    printf 'NODES_USER_%s="stubuser"\n' "$upper"
    printf 'NODES_PASSWORD_%s="stubpass"\n' "$upper"
  done
} >"${ETC_DIR}/nodes.conf"
chmod 0600 "${ETC_DIR}/nodes.conf"

# telegram.conf is the delivery configuration; the same credential is used by the
# management bot, which has its own file.
cat >"${ETC_DIR}/telegram.conf" <<EOF
TELEGRAM_BOT_TOKEN="${TOKEN}"
TELEGRAM_CHAT_ID="555000111"
TELEGRAM_BACKUP_ENABLED="1"
TELEGRAM_BACKUP_SCHEDULE="daily"
TELEGRAM_BACKUP_KEEP_REMOTE="7"
EOF
cat >"${ETC_DIR}/telegram_bot.conf" <<EOF
TELEGRAM_BOT_TOKEN="${TOKEN}"
TELEGRAM_BOT_USERS="1001:root,1002:viewer"
TELEGRAM_BOT_CHATS="1001:555000111,1002:555000112"
TELEGRAM_BOT_POLL_TIMEOUT="0"
TELEGRAM_BOT_BACKUP_PASSWORD=""
EOF
chmod 0600 "${ETC_DIR}/telegram.conf" "${ETC_DIR}/telegram_bot.conf"

step "service doubles"
start_stub panel "$PANEL_PORT" || true
start_stub telegram "$TELEGRAM_PORT" || true
check "the panel service answers a request" curl -fsS "http://127.0.0.1:${PANEL_PORT}/marzban/api/admin/token" \
  -d 'username=stubuser&password=stubpass'
check "the telegram service answers a request" curl -fsS "http://127.0.0.1:${TELEGRAM_PORT}/bot${TOKEN}/getMe"

step "node management"
expect_output "a node is registered through the panel API" "registered in" \
  hub --nodes add marzban node-1 default 10.9.9.9 62050
record="${STATE}/nodes/marzban.node-1.conf"
check "the node record exists" test -f "$record"
check "the node record mode is 0600" test "$(stat -c '%a' "$record")" = "600"
check "the record holds one key per line" test "$(grep -c '^[A-Z_]*=' "$record")" -ge 6
check "the identifier the panel returned is recorded" grep -q '^NODE_REMOTE_ID=2$' "$record"
expect_output "the registered node is listed" "node-1" hub --nodes list
expect_output "the panel view lists the seeded node too" "existing-1" hub --nodes panel-list marzban
expect_output "the node status is read from the panel" "connected" hub --nodes show marzban node-1
expect_output "a restart is accepted by the panel" "accepted a restart" hub --nodes restart marzban node-1
check "the restart used the identifier the panel returned" grep -q '/api/node/2/restart' "${STUB_DIR}/panel-requests.jsonl"
expect_output "the panel log is printed" "stub node log line" hub --nodes logs marzban node-1
expect_output "a node wider than the API is refused" "Invalid address" hub --nodes add marzban node-2 default 'not a host' 62050
expect_output "a node registered twice is refused" "already registered" \
  hub --nodes add marzban node-1 default 10.9.9.9 62050
cp "${ETC_DIR}/nodes.conf" "$WORK/nodes.conf.good"
# Marzban authenticates its node calls with a session opened from a user name and
# a password, so the password is the credential that must be refused. Rebecca
# authenticates with its API token, so the token is the one that must be refused.
printf 'NODES_PASSWORD_MARZBAN="wrong-password"\n' >>"${ETC_DIR}/nodes.conf"
expect_output "a refused password stops the registration" "refused" \
  hub --nodes add marzban node-3 default 10.9.9.10 62050
check "a refused registration left no record" test ! -e "${STATE}/nodes/marzban.node-3.conf"
printf 'NODES_API_TOKEN_REBECCA="wrong-token"\n' >>"${ETC_DIR}/nodes.conf"
expect_output "a refused token stops the registration" "refused" \
  hub --nodes add rebecca node-3 default 10.9.9.10 62050
check "the refused token left no record" test ! -e "${STATE}/nodes/rebecca.node-3.conf"
cp "$WORK/nodes.conf.good" "${ETC_DIR}/nodes.conf"
expect_output "a node is deregistered in the panel" "was deregistered" hub --nodes remove marzban node-1
check "the local record is removed" test ! -e "$record"
check "the deregistration addressed the identifier the panel returned" \
  grep -q '"path": "/api/node/2"' "${STUB_DIR}/panel-requests.jsonl"

step "migration between panels"
expect_output "the supported pairs are published" "marzban" hub --migration pairs
expect_output "the preview reads the source panel" "user-a" hub --migration preview marzban pasarguard
if hub --migration run marzban pasarguard >"$WORK/migration.log" 2>&1; then
  ok "the migration completed"
else
  no "the migration completed"
  cat "$WORK/migration.log" >&2
fi
check "every source user was created at the destination" \
  test "$(grep -c '"panel": "pasarguard", "method": "POST", "path": "/api/user"' "${STUB_DIR}/panel-requests.jsonl")" -ge 3
check "the source panel received no write" test "$(grep -c '"panel": "marzban", "method": "POST", "path": "/api/user"' "${STUB_DIR}/panel-requests.jsonl")" -eq 0

step "backup delivery"
expect_output "the delivery reports its configuration" "configured" hub --backup-deliver status
expect_output "a delivery test reaches the chat" "delivered" hub --backup-deliver test
check "the chat received the test message" grep -q '"method": "sendMessage"' "${STUB_DIR}/telegram-requests.jsonl"
expect_output "a backup is created and sent" "delivered" hub --backup-deliver send
check "the archive was uploaded" grep -q '"method": "sendDocument"' "${STUB_DIR}/telegram-requests.jsonl"
archive="$(grep -o '[0-9]\{8\}T[0-9]\{6\}Z\.tar\.gz' "${STUB_DIR}/telegram-requests.jsonl" | tail -n 1)"
check "the uploaded file is the archive that was created" \
  test -n "$archive" -a -f "${BACKUP_DIR}/${archive}"
expect_output "the delivery ledger records that archive" "$archive" hub --backup-deliver ledger
check "the token appears in no BaToHub log" test "$(grep -rc "$TOKEN" "$LOGS" | grep -cv ':0$' || true)" = "0"

step "alerts"
expect_output "the alert types are listed" "disk_usage" hub --alerts types
expect_output "the outdated version alert is listed" "version_outdated" hub --alerts types
# No alert is enabled until an operator enables it, so a run with a condition that
# holds still delivers nothing.
hub --alerts threshold disk_usage 1 >/dev/null 2>&1
check "an alert nobody enabled is reported as disabled" \
  bash -c "'$COMMAND' --alerts status | grep -q '^disk_usage *no'"
replies_before="$(grep -c '\"method\": \"sendMessage\"' "${STUB_DIR}/telegram-requests.jsonl" || true)"
hub --alerts run >/dev/null 2>&1 || true
replies_after="$(grep -c '\"method\": \"sendMessage\"' "${STUB_DIR}/telegram-requests.jsonl" || true)"
check "a disabled alert delivers nothing" test "$replies_before" = "$replies_after"
hub --alerts enable disk_usage >/dev/null 2>&1
expect_output "the enabled alert is reported as enabled" "yes" hub --alerts status
if hub --alerts run >"$WORK/alerts.log" 2>&1; then
  ok "the alert run completed"
else
  no "the alert run completed"
  cat "$WORK/alerts.log" >&2
fi
check "the alert reached the chat" grep -q 'disk' "${STUB_DIR}/telegram-requests.jsonl"
check "the delivered alert carries the configured threshold" \
  grep -q 'threshold 1%' "${STUB_DIR}/telegram-requests.jsonl"
before="$(grep -c '"method": "sendMessage"' "${STUB_DIR}/telegram-requests.jsonl")"
hub --alerts run >/dev/null 2>&1 || true
after="$(grep -c '"method": "sendMessage"' "${STUB_DIR}/telegram-requests.jsonl")"
check "the cooldown suppresses a repeated alert" test "$before" = "$after"
hub --alerts disable disk_usage >/dev/null 2>&1 || true
check "the disabled alert is reported as disabled" \
  bash -c "'$COMMAND' --alerts status | grep -q '^disk_usage *no'"

step "management bot"
expect_output "the bot reports its configuration" "configured" hub --bot status
expect_output "a listed account is authorised" "authorised" hub --bot check 1001 555000111
expect_output "an unlisted account is refused" "refused" hub --bot check 9999
if hub --bot once >"$WORK/bot.log" 2>&1; then
  ok "one polling round completed"
else
  no "one polling round completed"
  cat "$WORK/bot.log" >&2
fi
check "the bot answered the authorised account" \
  grep -q 'BaToHub management bot' "${STUB_DIR}/telegram-requests.jsonl"
# The reply to /panels spans several lines. It arrives whole, which is what proves
# that a multi-line form value survives the transport.
check "the bot answered /panels with the whole panel list" \
  python3 - "${STUB_DIR}/telegram-requests.jsonl" <<'PY'
import json
import sys

names = ["Rebecca", "Marzban", "PasarGuard", "3X-UI (Sanaei)", "VPN-UI"]
for line in open(sys.argv[1], encoding="utf-8"):
    record = json.loads(line)
    if record.get("method") != "sendMessage":
        continue
    if all(name in record.get("text", "") for name in names):
        sys.exit(0)
sys.exit(1)
PY
check "a command from an unlisted account was refused" grep -q 'refused user=9999 reason=not_listed' "${LOGS}/telegram-bot.log"
# The refusal is silent: the chat of the unlisted account receives no message.
check "the refused account received no reply" \
  bash -c "! grep -q '\"chat_id\": \"555000999\"' '${STUB_DIR}/telegram-requests.jsonl'"
printf 'viewer-pass\n' | hub admin add viewer read-only >"$WORK/admin-add.log" 2>&1 || true
expect_output "the created account is listed" "viewer" hub admin list
expect_output "a read-only account holds no panel permission" "denied" \
  hub_as_viewer admin check panels.install
expect_output "a read-only account may view" "allowed" \
  hub_as_viewer admin check panels.view
check "the built-in root account cannot be removed" \
  bash -c "'$COMMAND' admin remove root >/dev/null 2>&1 && exit 1 || exit 0"
expect_output "the permission table is published" "admins.manage" hub admin permissions
check "the manager account was created" test -r "${ETC_DIR}/admins.conf"
check "the account file mode is 0600" test "$(stat -c '%a' "${ETC_DIR}/admins.conf")" = "600"
check "no password is stored in clear text" bash -c "! grep -q 'viewer-pass' '${ETC_DIR}/admins.conf'"

step "reports"
expect_output "the report names are listed" "users" hub --reports list
expect_output "the per-user traffic report renders on screen" "user-a" hub --reports show user_traffic screen
expect_output "the user count report renders on screen" "marzban" hub --reports show user_counts screen
if hub --reports export user_counts csv >"$WORK/report.log" 2>&1; then
  ok "a report is exported as csv"
else
  no "a report is exported as csv"
  cat "$WORK/report.log" >&2
fi
check "the export is on disk" test -n "$(find "${STATE}/reports" -name '*.csv' -print -quit 2>/dev/null)"
check "the export mode is 0600" test "$(stat -c '%a' "$(find "${STATE}/reports" -name '*.csv' -print -quit)")" = "600"
expect_output "the exports are listed" "csv" hub --reports exports
if hub --reports rotate 1 >"$WORK/rotate.log" 2>&1; then
  ok "the export history can be rotated"
else
  no "the export history can be rotated"
  cat "$WORK/rotate.log" >&2
fi

step "server tools"
expect_output "the firewall state is reported" "ufw" hub --server firewall status
expect_output "the bbr state is reported" "tcp_congestion_control" hub --server bbr status
expect_output "the limits are reported" "ulimit" hub --server limits show
expect_output "the time state is reported" "Current time" hub --server time status

step "ssl configuration for several names"
expect_output "a panel name is registered" "Registered panel.example.com" hub --ssl register rebecca panel.example.com panel http-01
expect_output "a second purpose is registered" "Registered sub.example.com" hub --ssl register rebecca sub.example.com subscription http-01
expect_output "the registered names are listed" "sub.example.com" hub --ssl list
check "the panel ssl file mode is 0600" test "$(stat -c '%a' "$(find "${ETC_DIR}/ssl" -name '*.conf' -print -quit)")" = "600"
expect_output "the ssl status is reported" "Rebecca" hub --ssl status rebecca
expect_output "an unregistered name is refused for revocation" "not registered" hub --ssl revoke rebecca other.example.com
expect_output "a name is unregistered" "Removed sub.example.com" hub --ssl unregister rebecca sub.example.com

step "container mode detection"
mkdir -p "${WORK}/fakebin"
cat >"${WORK}/fakebin/docker" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
info) exit 0 ;;
--version) printf 'Docker version 27.0.0, build stub\n' ;;
ps) printf 'x-ui\tUp 2 hours\n' ;;
inspect) printf 'running\n' ;;
exec) printf 'stub exec output\n' ;;
logs) printf 'stub container log line\n' ;;
stats) printf 'container x-ui cpu 1.00%% memory 10MiB / 1GiB\n' ;;
esac
exit 0
EOF
chmod +x "${WORK}/fakebin/docker"
expect_output "the panel is detected as a container" "container" \
  hub_with_docker --container mode rebecca
expect_output "the container status is read" "x-ui" hub_with_docker --container list
expect_output "the container log is read through the runtime" "stub container log line" \
  hub_with_docker --container logs rebecca
check "a panel without a runtime is reported as native" \
  bash -c "'$COMMAND' --container mode vpn-ui 2>&1 | grep -q 'native' || true"

step "secret handling"
for file in "${ETC_DIR}/nodes.conf" "${ETC_DIR}/telegram.conf" "${ETC_DIR}/telegram_bot.conf" "${ETC_DIR}/admins.conf"; do
  check "$(basename "$file") stays at mode 0600" test "$(stat -c '%a' "$file")" = "600"
done
check "no BaToHub log holds the bot token" bash -c "! grep -rq '$TOKEN' '$LOGS'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
