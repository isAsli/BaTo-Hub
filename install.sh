#!/usr/bin/env bash
set -Eeuo pipefail

# BaToHub installer.
#
# Sources, in strict order of preference:
#   1. BATOHUB_SOURCE_DIR - an existing release tree (used by the verification
#      scripts and by offline installs). Nothing is downloaded.
#   2. A release tree next to this script, when it looks like a release.
#   3. The release asset of a pinned tag: BaToHub-<version>.zip verified against
#      its published .sha256 sidecar AND the sha256 recorded in the release
#      manifest.json. Both must match before anything is extracted.
#   4. The tagged source archive for the same tag (used only when the zip asset
#      is missing). No checksum is published for this archive, so the failure to
#      verify is stated plainly in the log and on the console.
#
# The one-liner pipes this file from the main branch of the repository, but the
# release content it installs always comes from a pinned tag. The branch is the
# bootstrap transport for the script itself; it is never a content source.

STEP="startup"
# Set when a snapshot of a previous installation exists. The ERR trap restores
# it, so a failure at any step after the snapshot leaves the server as it was.
SNAPSHOT_DIR=""
HAD_INSTALLATION=0
restore_snapshot_on_error() {
  if [[ "$HAD_INSTALLATION" -eq 1 && -n "${SNAPSHOT_DIR:-}" && -d "${SNAPSHOT_DIR:-}" ]]; then
    printf '[install] restoring the previous installation from the snapshot\n'
    rm -rf -- "${INSTALL_DIR:?}"
    if install -d -m 0755 -o root -g root "$INSTALL_DIR" &&
      cp -a "${SNAPSHOT_DIR}/." "${INSTALL_DIR}/"; then
      printf '[install] previous installation restored from %s\n' "$SNAPSHOT_DIR"
    else
      printf '[install] RESTORE FAILED; the snapshot is still available at %s\n' "$SNAPSHOT_DIR" >&2
    fi
  elif [[ "$HAD_INSTALLATION" -eq 0 && -n "${SNAPSHOT_DIR:-}" && -d "${SNAPSHOT_DIR:-}" ]]; then
    rm -rf -- "$SNAPSHOT_DIR"
  fi
}
on_error() {
  restore_snapshot_on_error
  printf '\nERROR: BaToHub installation failed at step: %s\n' "$STEP" >&2
  printf 'The previous installation was restored. Review the log entries above and run the installer again.\n' >&2
  exit 1
}
trap on_error ERR

BATOHUB_REPO="${BATOHUB_REPO:-isAsli/BaTo-Hub}"
BATOHUB_RELEASE_TAG="${BATOHUB_RELEASE_TAG:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/batohub}"
CONFIG_DIR="${CONFIG_DIR:-/etc/batohub}"
STATE_DIR="${STATE_DIR:-/var/lib/batohub}"
LOG_DIR="${LOG_DIR:-/var/log/batohub}"
GLOBAL_CMD_NAME="${GLOBAL_CMD_NAME:-/usr/local/bin/BaToHub}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

# Timestamped log file for every installation step. Log lines never contain
# credentials or private material; they record what was downloaded and what was
# changed.
LOG_FILE="${LOG_DIR}/install.log"
install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
if [[ ! -e "$LOG_FILE" ]]; then
  install -m 0640 -o root -g root /dev/null "$LOG_FILE" 2>/dev/null || touch "$LOG_FILE"
fi
exec > >(
  while IFS= read -r line; do
    printf '%s\n' "$line"
    printf '[%s] %s\n' "$(date '+%F %T%z')" "$line" >>"$LOG_FILE" 2>/dev/null || true
  done
) 2>&1

log_line() {
  printf '[install] %s\n' "$1"
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

STEP="release tag resolution"
release_tag=""
if [[ -n "$BATOHUB_RELEASE_TAG" ]]; then
  release_tag="$BATOHUB_RELEASE_TAG"
  log_line "release tag from environment: ${release_tag}"
else
  release_api="https://api.github.com/repos/${BATOHUB_REPO}/releases/latest"
  # The latest published release is the pinned source. The main branch is never
  # used as a content source.
  release_tag="$(curl --fail --silent --show-error --retry 3 --proto '=https' \
    --tlsv1.2 --header 'Accept: application/vnd.github+json' "$release_api" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
fi
if [[ -z "$release_tag" ]]; then
  fail "no release tag could be resolved. Set BATOHUB_RELEASE_TAG to the tag to install."
fi
release_version="${release_tag#v}"
log_line "pinned release: ${release_tag} (version ${release_version})"

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
  if [[ -n "$script_path" && -f "$script_path" && "$script_path" != /dev/fd/* ]]; then
    candidate="$(cd "$(dirname "$script_path")" && pwd)"
    if [[ -r "${candidate}/VERSION" && -d "${candidate}/panels" ]]; then
      source_dir="$candidate"
    fi
  fi
fi

if [[ -n "$source_dir" ]]; then
  local_version="$(head -n 1 "${source_dir}/VERSION" | tr -d '[:space:]')"
  log_line "installing from the local tree: ${source_dir} (version ${local_version})"
else
  STEP="release asset download"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/batohub.install.XXXXXX")"
  manifest_url="https://github.com/${BATOHUB_REPO}/releases/download/${release_tag}/manifest.json"
  # --location is required: a release asset URL answers with a redirect to the
  # object store, and without it curl stores the empty redirect body and
  # reports success. --proto-redir keeps the redirect on HTTPS.
  if curl --fail --silent --show-error --retry 3 --location \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --output "${temp_dir}/manifest.json" "$manifest_url" &&
    [[ -s "${temp_dir}/manifest.json" ]]; then
    manifest_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${temp_dir}/manifest.json" | head -n 1 || true)"
    manifest_sha256="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${temp_dir}/manifest.json" | head -n 1 || true)"
    manifest_package="$(sed -n 's/.*"package"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${temp_dir}/manifest.json" | head -n 1 || true)"
    log_line "release manifest read: version ${manifest_version:-unknown}"
    [[ "$manifest_version" == "$release_version" ]] ||
      fail "manifest.json reports version ${manifest_version:-unknown}, expected ${release_version}."
  else
    manifest_version=""
    manifest_sha256=""
    manifest_package=""
    log_line "the manifest.json asset is not available for ${release_tag}"
  fi

  asset_name="BaToHub-${release_version}.zip"
  asset_url="${manifest_package:-https://github.com/${BATOHUB_REPO}/releases/download/${release_tag}/${asset_name}}"
  checksum_url="${asset_url}.sha256"
  asset_downloaded=0

  if curl --fail --silent --show-error --retry 3 --location \
    --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --output "${temp_dir}/${asset_name}" "$asset_url"; then
    asset_downloaded=1
    log_line "release asset downloaded: ${asset_name}"
  else
    log_line "the release asset is not available: ${asset_url}"
  fi

  if [[ "$asset_downloaded" -eq 1 ]]; then
    STEP="release asset verification"
    checksum_ok=0
    if curl --fail --silent --show-error --retry 3 --location \
      --proto '=https' --proto-redir '=https' \
      --tlsv1.2 --output "${temp_dir}/${asset_name}.sha256" "$checksum_url"; then
      if (cd "$temp_dir" && sha256sum -c "${asset_name}.sha256" >/dev/null 2>&1); then
        checksum_ok=1
        log_line "SHA-256 verified against the published .sha256 asset"
      else
        fail "SHA-256 verification against ${asset_name}.sha256 failed. The download is not trusted."
      fi
    else
      log_line "the .sha256 asset is not available: ${checksum_url}"
    fi
    if [[ "$checksum_ok" -eq 0 ]]; then
      if [[ -z "$manifest_sha256" ]]; then
        fail "no published checksum is available for ${asset_name}; refusing to extract an unverified download."
      fi
      actual_sha256="$(sha256sum "${temp_dir}/${asset_name}" | awk '{print $1}')"
      [[ "$actual_sha256" == "$manifest_sha256" ]] ||
        fail "SHA-256 mismatch: manifest.json expects ${manifest_sha256}, downloaded archive hashes to ${actual_sha256}."
      log_line "SHA-256 verified against the manifest.json asset"
    fi

    STEP="release asset extraction"
    tree_dir="${temp_dir}/tree"
    mkdir -p "$tree_dir"
    if command -v unzip >/dev/null 2>&1; then
      if ! unzip -q -o "${temp_dir}/${asset_name}" -d "$tree_dir"; then
        fail "the release zip could not be extracted"
      fi
    elif ! python3 -m zipfile -e "${temp_dir}/${asset_name}" "$tree_dir"; then
      fail "the release zip could not be extracted"
    fi
    if [[ ! -r "${tree_dir}/VERSION" ]]; then
      fail "the extracted release does not contain a VERSION file"
    fi
    extracted_version="$(head -n 1 "${tree_dir}/VERSION" | tr -d '[:space:]')"
    [[ "$extracted_version" == "$release_version" ]] ||
      fail "the extracted release reports version ${extracted_version}, expected ${release_version}."
    log_line "release tree extracted to ${tree_dir}"
    source_dir="$tree_dir"
  else
    STEP="tagged source archive download"
    archive_url="https://github.com/${BATOHUB_REPO}/archive/refs/tags/${release_tag}.tar.gz"
    log_line "falling back to the tagged source archive: ${archive_url}"
    if ! curl --fail --location --show-error --retry 3 \
      --proto '=https' --proto-redir '=https' \
      --tlsv1.2 --output "${temp_dir}/source.tar.gz" "$archive_url"; then
      fail "the tagged source archive could not be downloaded from ${archive_url}"
    fi
    log_line "tagged source archive SHA-256: $(sha256sum "${temp_dir}/source.tar.gz" | awk '{print $1}')"
    if ! tar -xzf "${temp_dir}/source.tar.gz" -C "$temp_dir" --strip-components=1; then
      fail "the downloaded source archive could not be extracted"
    fi
    if [[ ! -r "${temp_dir}/VERSION" ]]; then
      fail "the downloaded archive does not contain a VERSION file"
    fi
    source_version="$(head -n 1 "${temp_dir}/VERSION" | tr -d '[:space:]')"
    [[ "$source_version" == "$release_version" ]] ||
      fail "the source archive reports version ${source_version}, expected ${release_version}."
    log_line "note: no published checksum exists for the tagged source archive; the tag and the reported version are the only anchors"
    source_dir="$temp_dir"
  fi
fi

release_version="$(head -n 1 "${source_dir}/VERSION" | tr -d '[:space:]')"
log_line "installing BaToHub ${release_version} from ${source_dir}"

STEP="directory creation"
install -d -m 0750 -o root -g root "$INSTALL_DIR" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" \
  "${STATE_DIR}/locks" "${STATE_DIR}/backups"

STEP="installation snapshot"
# A snapshot of the previous tree is taken before anything is replaced. It is
# restored by the ERR trap when any later step fails and removed only after a
# complete success.
if [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
  HAD_INSTALLATION=1
  SNAPSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/batohub.snapshot.XXXXXX")"
  if ! cp -a "${INSTALL_DIR}/." "${SNAPSHOT_DIR}/"; then
    rm -rf -- "$SNAPSHOT_DIR"
    SNAPSHOT_DIR=""
    fail "a snapshot of the existing installation could not be created; nothing was replaced"
  fi
  log_line "previous installation snapshot: ${SNAPSHOT_DIR}"
else
  log_line "no previous installation found; this is a fresh install"
fi

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
log_line "release files copied into ${INSTALL_DIR}"

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
install -m 0640 -o root -g root /dev/null "${LOG_DIR}/batohub.log" 2>/dev/null ||
  touch "${LOG_DIR}/batohub.log"

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

if [[ -n "$SNAPSHOT_DIR" && -d "$SNAPSHOT_DIR" ]]; then
  rm -rf -- "$SNAPSHOT_DIR"
  SNAPSHOT_DIR=""
  log_line "installation snapshot removed"
fi

printf '\n'
log_line "installation complete"
printf '\nBaToHub %s is installed at %s\n' "$release_version" "$INSTALL_DIR"
printf 'Run: BaToHub\n'
printf '\nPost-install verification:\n'
printf '  BaToHub --version          Print the installed version\n'
printf '  BaToHub --validate         Validate every panel and tool interface\n'
printf '  BaToHub --status           Print the current status summary\n'
printf '\nDocumentation: see DOCS.md in the release; the security model is in\n'
printf 'SECURITY.md.\n'
