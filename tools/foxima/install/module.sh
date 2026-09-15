#!/usr/bin/env bash
set -Eeuo pipefail

# Foxima installation steps.
#
# The official installer is downloaded over HTTPS and executed where the operator
# asked for it. Prerequisites are checked first so a missing PHP runtime or
# database server is reported before anything is downloaded.

foxima_check_prerequisites() {
  local missing=0
  if ! need_cmd php; then
    warn "PHP was not found. Foxima requires a PHP runtime."
    missing=1
  fi
  if ! need_cmd mysql && ! need_cmd mariadb; then
    warn "Neither the mysql nor the mariadb client was found. Foxima requires a database server."
    missing=1
  fi
  if ! need_cmd curl; then
    err "curl is required to download the Foxima installer."
    return 1
  fi
  if [[ "$missing" -eq 1 ]]; then
    printf 'Install the missing packages, or run Foxima from the hosting control panel\n'
    printf 'that already provides PHP and a database server.\n'
    return 1
  fi
  return 0
}

tool_install_impl() {
  need_root || return 1
  local target tmp
  printf 'Foxima installation wizard\n'
  printf 'Source: %s\n\n' "$FOXIMA_REPO_URL"
  if ! foxima_check_prerequisites; then
    return 1
  fi
  target="$(trim "$(ui_prompt 'Install directory [/var/www/foxima]: ' '/var/www/foxima')")"
  [[ -n "$target" ]] || target="/var/www/foxima"
  if [[ "$target" == "/" || "$target" == /etc* || "$target" == /usr* || "$target" == /var/lib/batohub* ]]; then
    err "Refusing to install Foxima into a system directory: $target"
    return 1
  fi
  if [[ -d "$target" && -n "$(ls -A "$target" 2>/dev/null || true)" ]]; then
    if ! ui_confirm "The directory ${target} is not empty. Continue?"; then
      printf 'Nothing was installed.\n'
      return 0
    fi
  fi
  printf 'The official installer is interactive and may ask questions of its own.\n\n'
  tmp="$(mktemp_file foxima)"
  if ! curl --fail --location --show-error --silent --retry 3 --proto '=https' \
    --tlsv1.2 --output "$tmp" "$FOXIMA_INSTALLER_URL"; then
    rm -f -- "$tmp"
    err "The Foxima installer could not be downloaded from ${FOXIMA_INSTALLER_URL}"
    return 1
  fi
  install -d -m 0755 -o root -g root "$target"
  if ! (cd "$target" && bash "$tmp") >>"$LOG_FILE" 2>&1; then
    rm -f -- "$tmp"
    err "The Foxima installer did not complete. Full output: ${LOG_FILE}"
    printf 'The install directory was left in place at %s.\n' "$target"
    return 1
  fi
  rm -f -- "$tmp"
  install -d -m 0750 -o root -g root "$(dirname "$(foxima_state_file)")"
  printf '%s\n' "$target" >"$(foxima_state_file)"
  harden_file "$(foxima_state_file)" 0640
  ok "Foxima installer finished. Installation directory recorded: ${target}"
  printf 'Complete the remaining setup in the Foxima web interface.\n'
}

tool_uninstall_impl() {
  need_root || return 1
  local recorded
  recorded="$(foxima_recorded_path)"
  if [[ -z "$recorded" ]]; then
    printf 'BaToHub has no record of installing Foxima on this server.\n'
    printf 'Only an installation that BaToHub performed can be removed from here.\n'
    printf 'Use the removal procedure of the hosting control panel that installed Foxima.\n'
    return 0
  fi
  printf 'BaToHub recorded this Foxima installation: %s\n' "$recorded"
  printf 'A backup copy is created before anything is removed.\n'
  if ! ui_confirm_phrase REMOVE "Remove ${recorded}?"; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  local backup
  backup="${STATE_DIR}/tools/foxima/removed-$(current_timestamp).tar.gz"
  install -d -m 0750 -o root -g root "$(dirname "$backup")"
  if ! tar --create --gzip --file "$backup" -C "$(dirname "$recorded")" "$(basename "$recorded")" >>"$LOG_FILE" 2>&1; then
    err "The backup copy could not be created; nothing was removed."
    return 1
  fi
  harden_file "$backup" 0600
  rm -rf -- "$recorded"
  rm -f -- "$(foxima_state_file)"
  ok "Foxima installation removed. A copy was kept at ${backup}"
}

tool_update_impl() {
  need_root || return 1
  printf 'Foxima is updated by running its official installer again.\n'
  tool_install_impl
}
