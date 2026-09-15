#!/usr/bin/env bash
set -Eeuo pipefail

# BaToHub installer.
#
# Works in three ways:
#   1. From a cloned or extracted release tree (node install.sh).
#   2. From the documented one-liner, where the script is piped into bash and the
#      release archive is downloaded over HTTPS.
#   3. Re-run on an installed server. Existing configuration, state and logs are
#      preserved, so the installer is safe to run again.

STEP="startup"
on_error() {
  printf '\nERROR: BaToHub installation failed at step: %s\n' "$STEP" >&2
  printf 'Nothing else was changed. Review the message above and run the installer again.\n' >&2
  exit 1
}
trap on_error ERR

INSTALL_DIR="${INSTALL_DIR:-/opt/batohub}"
CONFIG_DIR="${CONFIG_DIR:-/etc/batohub}"
STATE_DIR="${STATE_DIR:-/var/lib/batohub}"
LOG_DIR="${LOG_DIR:-/var/log/batohub}"
GLOBAL_CMD_NAME="${GLOBAL_CMD_NAME:-/usr/local/bin/BaToHub}"
RELEASE_TARBALL_URL="${BATOHUB_TARBALL_URL:-https://github.com/isAsli/BaTo-Hub/archive/refs/heads/main.tar.gz}"

log_line() {
  printf '[install] %s\n' "$1"
}
fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

STEP="root check"
if [[ "$(id -u)" -ne 0 ]]; then
  printf 'ERROR: the installer requires root privileges.\n' >&2
  printf 'Run it with sudo, or as root.\n' >&2
  exit 1
fi

STEP="operating system detection"
os_id="unknown"
os_version="unknown"
if [[ -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s' "${ID:-unknown}")"
  # shellcheck source=/dev/null
  os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")"
fi
log_line "detected system: ${os_id} ${os_version}"
case "$os_id" in
ubuntu | debian) ;;
*)
  log_line "this system is not Ubuntu or Debian; package installation is skipped"
  ;;
esac

STEP="dependency check"
required_commands=(curl tar gzip python3 openssl)
optional_commands=(rsync flock)

missing_commands=()
for command_name in "${required_commands[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || missing_commands+=("$command_name")
done

if [[ "${#missing_commands[@]}" -gt 0 ]]; then
  case "$os_id" in
  ubuntu | debian)
    STEP="dependency installation"
    log_line "installing missing packages: ${missing_commands[*]}"
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get update -qq; then
      fail "apt-get update failed. The package lists could not be refreshed."
    fi
    packages=(ca-certificates)
    for command_name in "${missing_commands[@]}"; do
      case "$command_name" in
      curl) packages+=(curl) ;;
      tar) packages+=(tar) ;;
      gzip) packages+=(gzip) ;;
      python3) packages+=(python3) ;;
      openssl) packages+=(openssl) ;;
      *) fail "no package mapping is defined for the missing command: $command_name" ;;
      esac
    done
    packages+=(rsync util-linux)
    if ! apt-get install -y -qq "${packages[@]}"; then
      fail "the required packages could not be installed: ${packages[*]}"
    fi
    ;;
  *)
    fail "missing required commands (${missing_commands[*]}) and this system is not Ubuntu or Debian, so they cannot be installed automatically."
    ;;
  esac
fi

for command_name in "${required_commands[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required command is still missing after installation: $command_name"
done
for command_name in "${optional_commands[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 ||
    log_line "optional command not found: $command_name (some features degrade gracefully)"
done

STEP="release source resolution"
source_dir=""
temp_dir=""
cleanup_temp() {
  if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
    rm -rf -- "$temp_dir"
  fi
}
trap 'cleanup_temp' EXIT

if [[ -n "${BATOHUB_SOURCE_DIR:-}" && -r "${BATOHUB_SOURCE_DIR}/VERSION" ]]; then
  source_dir="$BATOHUB_SOURCE_DIR"
else
  script_path="${BASH_SOURCE[0]:-}"
  if [[ -n "$script_path" && -f "$script_path" ]]; then
    candidate="$(cd "$(dirname "$script_path")" && pwd)"
    if [[ -r "${candidate}/VERSION" && -d "${candidate}/panels" ]]; then
      source_dir="$candidate"
    fi
  fi
fi

if [[ -z "$source_dir" ]]; then
  STEP="release download"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/batohub.install.XXXXXX")"
  log_line "downloading the release archive"
  if ! curl --fail --location --show-error --silent --retry 3 --proto '=https' \
    --tlsv1.2 --output "${temp_dir}/release.tar.gz" "$RELEASE_TARBALL_URL"; then
    fail "the release archive could not be downloaded from ${RELEASE_TARBALL_URL}"
  fi
  if ! tar -xzf "${temp_dir}/release.tar.gz" -C "$temp_dir" --strip-components=1; then
    fail "the downloaded release archive could not be extracted"
  fi
  if [[ ! -r "${temp_dir}/VERSION" ]]; then
    fail "the downloaded archive does not contain a VERSION file"
  fi
  source_dir="$temp_dir"
fi

release_version="$(head -n 1 "${source_dir}/VERSION" | tr -d '[:space:]')"
log_line "installing BaToHub ${release_version} from ${source_dir}"

STEP="directory creation"
install -d -m 0750 -o root -g root "$INSTALL_DIR" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" \
  "${STATE_DIR}/locks" "${STATE_DIR}/backups"

STEP="file installation"
preserve_dir=""
if [[ -f "${INSTALL_DIR}/config/panel.conf" || -f "${INSTALL_DIR}/config/batohub.conf" ]]; then
  preserve_dir="$(mktemp -d "${TMPDIR:-/tmp}/batohub.preserve.XXXXXX")"
  [[ -f "${INSTALL_DIR}/config/panel.conf" ]] && cp -a "${INSTALL_DIR}/config/panel.conf" "$preserve_dir/"
  [[ -f "${INSTALL_DIR}/config/batohub.conf" ]] && cp -a "${INSTALL_DIR}/config/batohub.conf" "$preserve_dir/"
fi

if command -v rsync >/dev/null 2>&1; then
  if ! rsync --archive --delete --exclude '.git/' --exclude 'node_modules/' \
    "${source_dir}/" "${INSTALL_DIR}/"; then
    fail "copying the release files into ${INSTALL_DIR} failed"
  fi
else
  for entry in "${source_dir}"/*; do
    [[ -e "$entry" ]] || continue
    [[ "$(basename "$entry")" == ".git" ]] && continue
    cp -a "$entry" "${INSTALL_DIR}/"
  done
fi

if [[ -n "$preserve_dir" ]]; then
  [[ -f "${preserve_dir}/panel.conf" ]] && cp -a "${preserve_dir}/panel.conf" "${INSTALL_DIR}/config/panel.conf"
  [[ -f "${preserve_dir}/batohub.conf" ]] && cp -a "${preserve_dir}/batohub.conf" "${INSTALL_DIR}/config/batohub.conf"
  rm -rf -- "$preserve_dir"
fi

STEP="configuration"
if [[ -f "${CONFIG_DIR}/batohub.conf" ]]; then
  log_line "existing configuration preserved: ${CONFIG_DIR}/batohub.conf"
else
  if [[ ! -f "${INSTALL_DIR}/config/batohub.conf" ]]; then
    fail "the release does not contain config/batohub.conf"
  fi
  cp -a "${INSTALL_DIR}/config/batohub.conf" "${CONFIG_DIR}/batohub.conf"
  log_line "configuration created: ${CONFIG_DIR}/batohub.conf"
fi
chmod 0600 "${CONFIG_DIR}/batohub.conf"
chown root:root "${CONFIG_DIR}/batohub.conf"
if [[ -f "${CONFIG_DIR}/panel.conf" ]]; then
  chmod 0600 "${CONFIG_DIR}/panel.conf"
  chown root:root "${CONFIG_DIR}/panel.conf"
fi

STEP="permissions"
chown -R root:root "$INSTALL_DIR" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
find "$INSTALL_DIR" -type d -exec chmod 0755 {} +
find "$INSTALL_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "${INSTALL_DIR}/bin/batohub" "${INSTALL_DIR}/bin/uninstall" 2>/dev/null || true
chmod 0750 "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
chmod 0755 "$INSTALL_DIR"
install -m 0640 -o root -g root /dev/null "${LOG_DIR}/batohub.log"

STEP="global command"
command_dir="$(dirname "$GLOBAL_CMD_NAME")"
if [[ ! -d "$command_dir" ]]; then
  if ! install -d -m 0755 -o root -g root "$command_dir"; then
    fail "the directory ${command_dir} does not exist and could not be created"
  fi
  log_line "created command directory: ${command_dir}"
fi
if [[ -e "$GLOBAL_CMD_NAME" && ! -L "$GLOBAL_CMD_NAME" ]]; then
  backup_command="${GLOBAL_CMD_NAME}.BaToHub-original"
  if [[ -e "$backup_command" ]]; then
    fail "${GLOBAL_CMD_NAME} already exists and a backup also exists at ${backup_command}; resolve this manually"
  fi
  mv -- "$GLOBAL_CMD_NAME" "$backup_command"
  log_line "existing file moved to ${backup_command}"
fi
ln -sfn "${INSTALL_DIR}/bin/batohub" "$GLOBAL_CMD_NAME"
if [[ "$(readlink "$GLOBAL_CMD_NAME")" != "${INSTALL_DIR}/bin/batohub" ]]; then
  fail "the global command link ${GLOBAL_CMD_NAME} could not be created"
fi
log_line "global command installed: ${GLOBAL_CMD_NAME}"

STEP="interface validation"
interface_output=""
if ! interface_output="$(BATOHUB_ROOT="$INSTALL_DIR" bash -c '
  set -Eeuo pipefail
  . "$BATOHUB_ROOT/lib/common.sh"
  . "$BATOHUB_ROOT/lib/panel_helpers.sh"
  . "$BATOHUB_ROOT/core/panel_loader.sh"
  loader_validate_all
')"; then
  printf '%s\n' "$interface_output"
  fail "one or more panels or tools do not expose the BaToHub interface"
fi
printf '%s\n' "$interface_output" | sed 's/^/[install] /'

STEP="integrity manifest"
if ! BATOHUB_ROOT="$INSTALL_DIR" bash -c '
  set -Eeuo pipefail
  . "$BATOHUB_ROOT/lib/common.sh"
  . "$BATOHUB_ROOT/security/integrity.sh"
  integrity_rebuild_and_verify
'; then
  fail "the integrity manifest could not be written and verified"
fi

STEP="final verification"
if ! BATOHUB_ROOT="$INSTALL_DIR" bash -c '
  set -Eeuo pipefail
  . "$BATOHUB_ROOT/lib/common.sh"
  . "$BATOHUB_ROOT/core/panel_loader.sh"
  . "$BATOHUB_ROOT/security/integrity.sh"
  integrity_check
'; then
  fail "the installed files do not match the integrity manifest"
fi

printf '\n'
log_line "installation complete"
printf '\nBaToHub %s is installed at %s\n' "$release_version" "$INSTALL_DIR"
printf 'Run: BaToHub\n'
printf '\nPost-install verification:\n'
printf '  BaToHub --version          Print the installed version\n'
printf '  BaToHub --validate         Validate every panel and tool interface\n'
printf '  BaToHub --status           Print the current status summary\n'
printf '\nDocumentation: see README.md in the release, and the SUPPORT document\n'
printf 'for support and bug reporting.\n'
