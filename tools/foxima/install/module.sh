#!/usr/bin/env bash
set -Eeuo pipefail

# Foxima installation and update steps.
#
# The official installer is the only component that deploys Foxima. It installs
# Docker when it is missing, downloads a release archive, writes the
# configuration and starts the Compose stack, and it decides the project
# directory itself. BaToHub runs it as supplied by its author, passes it the
# release argument its own command line documents, and records the directory it
# used. BaToHub never writes the Foxima configuration and never removes the
# stack or its data.
#
# Release argument, from the installer's own argument handling:
#   -v <tag>  install that published release
#   -beta     install the rolling build from the default branch
#   (nothing) the installer opens its own menu

# The commands the official installer uses to fetch and unpack a release.
foxima_check_prerequisites() {
  local missing=0 command_name
  if ! need_cmd curl; then
    err "curl is required to download the Foxima installer."
    return 1
  fi
  for command_name in wget unzip; do
    if ! need_cmd "$command_name"; then
      warn "$command_name was not found. The official Foxima installer uses it to fetch and unpack a release."
      missing=1
    fi
  done
  if ! need_cmd docker; then
    printf 'Docker is not installed. The official installer installs it when the\n'
    printf 'distribution it supports is detected.\n'
  fi
  if [[ "$missing" -eq 1 ]]; then
    printf 'Install the missing commands, then run the installation again.\n'
    return 1
  fi
  return 0
}

# The argument list the official installer expects for a version, one element
# per line. An empty list means the installer's own menu is used.
foxima_installer_argv() {
  local version="$1"
  case "$version" in
  "") return 0 ;;
  "$FOXIMA_CHANNEL_KEY") printf '%s\n' -beta ;;
  *) printf '%s\n' -v "$version" ;;
  esac
}

# Runs the official installer for one version and records the result.
foxima_install_version() {
  local version="${1:-}" dir before after
  panel_valid_version_string "$version" || return 1
  need_root || return 1
  if ! foxima_check_prerequisites; then
    return 1
  fi
  before="$(tool_version)"
  printf 'Foxima version before the installation: %s\n' "$before"
  printf 'Source: %s\n' "$FOXIMA_REPO_URL"
  printf 'The official installer deploys a Docker Compose stack and chooses the\n'
  printf 'project directory itself. Ports 80 and 443 must be free.\n\n'
  if [[ "$version" == "$FOXIMA_CHANNEL_KEY" ]]; then
    printf 'Installing the rolling build from the default branch.\n'
    panel_fetch_official_installer_args "$FOXIMA_INSTALLER_URL" -beta || {
      err "The Foxima installer did not complete. Full output: ${LOG_FILE}"
      return 1
    }
  else
    printf 'Installing release %s.\n' "$version"
    panel_fetch_official_installer_args "$FOXIMA_INSTALLER_URL" -v "$version" || {
      err "The Foxima installer did not complete. Full output: ${LOG_FILE}"
      return 1
    }
  fi
  dir="$(foxima_installed_path || true)"
  if [[ -z "$dir" ]]; then
    err "The installer finished but no Foxima installation was found."
    err "Expected the project directory at ${FOXIMA_PROJECT_DIR}."
    return 1
  fi
  foxima_record_path "$dir"
  after="$(tool_version)"
  printf 'Project directory: %s\n' "$dir"
  printf 'Installed version after the installation: %s\n' "$after"
  version_change_log foxima install "$before" "$after" "$version"
  ok "Foxima installation directory recorded: ${dir}"
  printf 'Complete the remaining setup in the Foxima interface, or with: %s\n' \
    "$FOXIMA_MANAGEMENT_CMD"
  return 0
}

# Installation with a version choice. The published releases come from the
# project's own repository; the newest stable release is the default.
tool_install_impl() {
  local version="${1:-}"
  need_root || return 1
  if [[ -z "$version" ]]; then
    ui_title "Install Foxima"
    printf 'Installed version: %s\n\n' "$(tool_version)"
    version="$(foxima_choose_version)" || return 1
  fi
  foxima_install_version "$version"
}

# Updating an existing installation is the job of the official management
# command the installer installs: it selects the version itself and it owns the
# configuration and the data volumes. BaToHub does not reimplement it and does
# not replace the stack.
tool_update_impl() {
  need_root || return 1
  local before
  before="$(tool_version)"
  printf 'Installed version: %s\n\n' "$before"
  if ! tool_detect; then
    err "Foxima is not installed on this server, so there is nothing to update."
    return 1
  fi
  if [[ ! -x "$FOXIMA_MANAGEMENT_CMD" ]]; then
    err "The official Foxima management command is not present: $FOXIMA_MANAGEMENT_CMD"
    err "It is installed by the official Foxima installer."
    err "Install or repair the installation before updating."
    return 1
  fi
  if [[ "$INTERACTIVE" != 1 ]]; then
    err "The official Foxima updater is an interactive menu and needs a terminal."
    err "Run it directly: $FOXIMA_MANAGEMENT_CMD"
    return 1
  fi
  printf 'Starting the official Foxima management menu.\n'
  printf 'It performs the update, including the selection of a release, and it owns\n'
  printf 'the configuration and the data of the installation.\n\n'
  "$FOXIMA_MANAGEMENT_CMD"
  printf '\nInstalled version after the update: %s\n' "$(tool_version)"
  version_change_log foxima update "$before" "$(tool_version)" official-menu
  return 0
}
