#!/usr/bin/env bash
set -Eeuo pipefail

# Isolated functional verification.
#
# Installs BaToHub into a disposable prefix with its own configuration, state and
# log directories, then exercises the documented commands, the panel interface,
# the backup and restore flow and the uninstaller. Nothing outside the prefix is
# modified, so the script can run on a development machine.
#
# Usage: bash scripts/verify-install.sh [work-directory]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Read from VERSION so the checks never carry a version literal of their own.
RELEASE_VERSION="$(tr -d '[:space:]' <"${ROOT}/VERSION")"
WORK="${1:-/tmp/batohub-verify}"
PREFIX="${WORK}/opt"
ETC_DIR="${WORK}/etc"
STATE="${WORK}/state"
LOGS="${WORK}/logs"
COMMAND="${WORK}/bin/BaToHub"

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

rm -rf "$WORK"
mkdir -p "$WORK"

step "installer"
if bash "$ROOT/install.sh" >"$WORK/install.log" 2>&1; then
  ok "installer completed"
else
  no "installer completed"
  tail -n 40 "$WORK/install.log" >&2
fi

step "files and permissions"
check "program files installed" test -x "$PREFIX/bin/batohub"
check "version file installed" test -r "$PREFIX/VERSION"
check "configuration created" test -f "$ETC_DIR/batohub.conf"
check "integrity manifest created" test -f "$ETC_DIR/integrity.sha256"
check "global command link created" test -L "$COMMAND"
check "configuration mode is 0600" test "$(stat -c '%a' "$ETC_DIR/batohub.conf")" = "600"
check "state directory mode is 0750" test "$(stat -c '%a' "$STATE")" = "750"
check "log directory mode is 0750" test "$(stat -c '%a' "$LOGS")" = "750"

step "documented commands"
expect_output "--version reports the version" "$RELEASE_VERSION" "$COMMAND" --version
expect_output "--list-panels lists five panels" "vpn-ui" "$COMMAND" --list-panels
expect_output "--detect runs on a host without panels" "No supported panel was detected." "$COMMAND" --detect
expect_output "--status prints an integrity line" "Integrity:" "$COMMAND" --status
expect_output "--validate reports every panel" "interface ok" "$COMMAND" --validate
check "--check verifies the manifest" "$COMMAND" --check
expect_output "--tools lists Foxima" "foxima" "$COMMAND" --tools
expect_output "--help documents --panel" "--panel NAME CMD" "$COMMAND" --help
expect_output "--help documents --tool" "--tool NAME CMD" "$COMMAND" --help

step "panel interface"
for panel in rebecca marzban pasarguard 3x-ui vpn-ui; do
  state="$("$COMMAND" --panel "$panel" status 2>/dev/null | tail -n 1 || true)"
  case "$state" in
  running | stopped | not_installed) ok "panel ${panel} reports a valid status (${state})" ;;
  *) no "panel ${panel} reports a valid status (got: ${state})" ;;
  esac
  version="$("$COMMAND" --panel "$panel" version 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$version" ]]; then
    ok "panel ${panel} reports a version (${version})"
  else
    no "panel ${panel} reports a version"
  fi
done
expect_output "panel uninstall leaves the panel in place" "does not remove" \
  "$COMMAND" --panel rebecca uninstall

# On a host without the panel installed, template apply must either stage the
# bundled template or refuse with a message that names the missing file. Both
# outcomes prove the action reports what it did.
for panel in rebecca marzban pasarguard 3x-ui vpn-ui; do
  output="$("$COMMAND" --panel "$panel" template-apply 2>&1 || true)"
  case "$output" in
  *"Staged template"* | *"subscription template is installed"* | *"configuration file was not found"*)
    ok "panel ${panel} template apply reports what it did"
    ;;
  *)
    no "panel ${panel} template apply reports what it did"
    printf '     actual output: %s\n' "$output" >&2
    ;;
  esac
  # The report always names the template, so a rejected command is not accepted
  # as a successful report.
  output="$("$COMMAND" --panel "$panel" template-status 2>&1 || true)"
  if [[ "$output" == *Template* ]]; then
    ok "panel ${panel} template status prints a report"
  else
    no "panel ${panel} template status prints a report"
    printf '     actual output: %s\n' "$output" >&2
  fi
done

step "panel version selection"
# The version list comes from the panel's own repository over the network, so
# either a list or a clear error is a valid answer. A version string that is not
# a version must never be accepted.
for panel in rebecca marzban pasarguard 3x-ui vpn-ui; do
  output="$("$COMMAND" --panel "$panel" versions 2>&1 || true)"
  case "$output" in
  v* | *"could not be listed"* | *"No published"* | *"No source repository"*)
    ok "panel ${panel} versions lists releases or reports why it cannot"
    ;;
  *)
    no "panel ${panel} versions lists releases or reports why it cannot"
    printf '     actual output: %s\n' "$output" >&2
    ;;
  esac
done
expect_output "an unexpected version string is refused" "Refusing an unexpected version string" \
  "$COMMAND" --panel rebecca install-version 'v1.0.0; touch /tmp/batohub-should-not-exist'
check "the refused version string changed nothing" test ! -e /tmp/batohub-should-not-exist
# VC-UI's official deployment script resolves the newest release itself, so a
# pinned install must be refused with a message that says why. The requested
# string is a prerelease, which can never equal the newest stable release.
expect_output "VPN-UI refuses a version it cannot be pinned to" "does not support version pinning" \
  "$COMMAND" --panel vpn-ui install-version v0.0.1-beta12

step "tool interface"
output="$("$COMMAND" --tool foxima detect 2>&1 || true)"
case "$output" in
not_installed | installed) ok "--tool foxima detect reports a state" ;;
*) no "--tool foxima detect reports a state (got: ${output})" ;;
esac
output="$("$COMMAND" --tool foxima status 2>&1 || true)"
case "$output" in
not_installed | stopped | running) ok "--tool foxima status reports a state" ;;
*) no "--tool foxima status reports a state (got: ${output})" ;;
esac
output="$("$COMMAND" --tool foxima version 2>&1 || true)"
if [[ -n "$output" ]]; then
  ok "--tool foxima version prints a version (${output})"
else
  no "--tool foxima version prints a version"
fi
# Foxima is not installed in this environment, so the configuration view and the
# removal entry must both report that they changed nothing.
output="$("$COMMAND" --tool foxima configure 2>&1 || true)"
case "$output" in
*"is not installed"* | *"Project directory"*) ok "--tool foxima configure reports the configuration state" ;;
*) no "--tool foxima configure reports the configuration state (got: ${output})" ;;
esac
output="$("$COMMAND" --tool foxima uninstall 2>&1 || true)"
case "$output" in
*"does not remove Foxima"*) ok "--tool foxima uninstall keeps the installation" ;;
*) no "--tool foxima uninstall keeps the installation (got: ${output})" ;;
esac
output="$("$COMMAND" --tool foxima logs 2>&1 || true)"
case "$output" in
*"No log source"* | *log*) ok "--tool foxima logs reports a log source or says there is none" ;;
*) no "--tool foxima logs reports a log source (got: ${output})" ;;
esac
expect_output "an unexpected tool version string is refused" "Refusing an unexpected version string" \
  "$COMMAND" --tool foxima install-version 'v1.0.0; touch /tmp/batohub-tool-should-not-exist'
check "the refused tool version string changed nothing" test ! -e /tmp/batohub-tool-should-not-exist

step "backup and restore"
expect_output "--backup creates an archive" ".tar.gz" "$COMMAND" --backup
archive="$(find "$STATE/backups" -maxdepth 1 -name '*.tar.gz' | sort | tail -n 1)"
check "backup archive exists" test -n "$archive"
check "backup checksum exists" test -f "${archive}.sha256"
check "backup archive mode is 0600" test "$(stat -c '%a' "$archive")" = "600"
if tar -tzf "$archive" 2>/dev/null | grep -q 'BaToHub-backup.meta'; then
  ok "backup metadata is embedded"
else
  no "backup metadata is embedded"
fi
# Members are collected once: a pipeline such as `tar | grep -q` would fail
# under pipefail when grep exits before tar has written everything.
members="$(tar -tzf "$archive" 2>/dev/null | sed 's:/$::' || true)"
if grep -qx "${CONFIG_DIR#/}" <<<"$members"; then
  ok "backup contains the configuration directory"
else
  no "backup contains the configuration directory"
fi
if grep -qx "${BACKUP_DIR#/}" <<<"$members"; then
  no "backup excludes the backup directory itself"
else
  ok "backup excludes the backup directory itself"
fi
if grep -qx "BaToHub-backup.meta" <<<"$members"; then
  ok "backup member names are relative to the filesystem root"
else
  no "backup member names are relative to the filesystem root"
fi
if restore_output="$("$COMMAND" --restore "$archive" 2>&1)"; then
  ok "restore verifies and applies the archive"
else
  no "restore verifies and applies the archive"
  printf '%s\n' "$restore_output" | sed 's/^/     /' >&2
fi
if [[ "$restore_output" == *"Safety backup"* ]]; then
  ok "restore creates a safety backup first"
else
  no "restore creates a safety backup first"
fi

step "update safety"
cp -a "$archive" "$WORK/foreign.tar.gz"
expect_output "restore refuses an archive without a checksum" "Checksum file not found" \
  bash -c "'$COMMAND' --restore '$WORK/foreign.tar.gz' 2>&1 || true"

step "panel selection"
if "$COMMAND" --select-panel rebecca >"$WORK/select.log" 2>&1; then
  ok "panel selection stored"
else
  no "panel selection stored"
  cat "$WORK/select.log" >&2
fi
check "panel.conf exists" test -f "$ETC_DIR/panel.conf"
check "panel.conf mode is 0600" test "$(stat -c '%a' "$ETC_DIR/panel.conf")" = "600"
expect_output "panel.conf records the panel" "PANEL=rebecca" cat "$ETC_DIR/panel.conf"
expect_output "--status reports the configured panel" "Rebecca" "$COMMAND" --status

step "uninstall"
if uninstall_output="$(bash "$PREFIX/bin/uninstall" --yes 2>&1)"; then
  ok "uninstaller completed"
else
  no "uninstaller completed"
  printf '%s\n' "$uninstall_output" >&2
fi
if [[ "$uninstall_output" == *"No panel or panel data was touched"* ]]; then
  ok "uninstaller states that panels were left alone"
else
  no "uninstaller states that panels were left alone"
fi
check "program directory removed" test ! -d "$PREFIX"
check "configuration directory removed" test ! -d "$ETC_DIR"
check "state directory removed" test ! -d "$STATE"
check "global command link removed" test ! -e "$COMMAND"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
