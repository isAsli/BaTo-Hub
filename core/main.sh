#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh
. /opt/batohub/core/license.sh
. /opt/batohub/core/module_loader.sh
. /opt/batohub/modules/rebecca/ssl/module.sh
. /opt/batohub/modules/rebecca/templates/module.sh
. /opt/batohub/modules/rebecca/rebecca_core.sh

load_module_list

banner() {
  printf '%s\n' "BaToHub - Central Server Manager"
  printf '%s\n' "Version: $APP_VERSION"
  printf '%s\n' "----------------------------------------"
}

header() {
  clear
  banner
}

pause() {
  read -r -p "Press Enter to continue..." _
}

confirm() {
  local message="$1"
  local answer
  printf '%s\n' "$message"
  read -r -p "Type YES to confirm: " answer
  if [ "${answer:-}" != "YES" ]; then
    info "Action cancelled."
    return 1
  fi
  return 0
}

confirm_destructive() {
  local message="$1"
  local answer
  printf '%s\n' "$message"
  read -r -p "Type REMOVE to confirm: " answer
  if [ "${answer:-}" != "REMOVE" ]; then
    info "Action cancelled."
    return 1
  fi
  return 0
}

server_menu() {
  while :; do
    header
    printf '%s\n' '1) Server information' '2) Running services' '3) System resources' '4) Network' '5) BaToHub logs' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1)
        header
        printf 'Hostname: '; hostname || true
        if [ -f /etc/os-release ]; then
          . /etc/os-release
          printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
        else
          printf 'OS: unknown\n'
        fi
        printf 'Kernel: '; uname -r || true
        printf 'Architecture: '; uname -m || true
        pause
        ;;
      2)
        header
        if command -v systemctl >/dev/null 2>&1; then
          systemctl --no-pager --type=service --state=running 2>/dev/null | head -n 35 || true
        else
          err "systemctl is not available."
        fi
        pause
        ;;
      3)
        header
        if command -v free >/dev/null 2>&1; then
          free -h || true
        fi
        echo
        if command -v df >/dev/null 2>&1; then
          df -h / /opt 2>/dev/null || true
        fi
        pause
        ;;
      4)
        header
        if command -v ip >/dev/null 2>&1; then
          ip -brief address 2>/dev/null || true
        fi
        echo
        if command -v ss >/dev/null 2>&1; then
          ss -lntup 2>/dev/null | head -n 40 || true
        fi
        pause
        ;;
      5)
        header
        if [ -f "$LOG_FILE" ]; then
          tail -n 80 "$LOG_FILE"
        else
          err "Log file not found: $LOG_FILE"
        fi
        pause
        ;;
      0) return;;
    esac
  done
}

update_all() {
  . /opt/batohub/core/update.sh
  update_all
}

update_module() {
  local module="$1"
  local json url
  json=""
  for json in "${MODULE_CACHE[@]}"; do
    if [ "$(get_module_name "$json")" = "$module" ]; then
      break
    fi
    json=""
  done
  if [ -z "$json" ]; then
    err "Module not found: $module"
    pause
    return
  fi
  if [ "$(get_module_status "$json")" != "active" ]; then
    err "$module is not active in this release."
    pause
    return
  fi
  url=$(json_get "$json" "update_url")
  if [ -z "$url" ]; then
    err "No update URL registered for $module."
    pause
    return
  fi

  header
  info "Updating $module..."
  local tmp
  tmp=$(mktemp_file "update_${module}")
  if curl -fsSL --max-time 20 --cacert /etc/ssl/certs/ca-certificates.crt "$url" -o "$tmp" 2>>"$LOG_FILE"; then
    if bash "$tmp" update 2>&1 | tee -a "$LOG_FILE"; then
      ok "Module update completed: $module"
    else
      err "Module update failed: $module"
      show_last_logs
    fi
    rm -f "$tmp"
  else
    err "Module updater unavailable: $module"
    rm -f "$tmp"
  fi
  pause
}

tools_menu() {
  while :; do
    header
    printf '%s\n' '1) Rebecca' '2) PasarGuard' '3) Sanaei / 3X-UI' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1)
        rebecca_menu
        ;;
      2)
        header
        pasarguard_menu
        ;;
      3)
        header
        threxiui_menu
        ;;
      0) return;;
    esac
  done
}

rebecca_menu() {
  while :; do
    header
    printf '%s\n' 'Rebecca'
    printf '%s\n' '--------------'
    printf '%s\n' '1) SSL'
    printf '%s\n' '2) Template / BaTo-Ui'
    printf '%s\n' '3) Update Rebecca'
    printf '%s\n' '4) Status'
    printf '%s\n' '5) Remove BaToHub changes'
    printf '%s\n' '6) Remove BaTo-Ui'
    printf '%s\n' '7) Rebecca logs'
    printf '%s\n' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1) ssl_menu;;
      2) templates_menu;;
      3) update_module "rebecca";;
      4)
        header
        if command -v systemctl >/dev/null 2>&1; then
          systemctl --no-pager status rebecca 2>&1 | head -n 45 || true
        else
          err "systemctl is not available."
        fi
        if [ -f /opt/rebecca/.env ]; then
          grep -E '^(UVICORN_SSL_CERTFILE|UVICORN_SSL_KEYFILE|REBECCA_CERT_BASE|CUSTOM_TEMPLATES_DIRECTORY|SUBSCRIPTION_PAGE_TEMPLATE)=' /opt/rebecca/.env || true
        fi
        pause
        ;;
      5)
        header
        if ! confirm_destructive 'Remove BaToHub template changes from Rebecca?'; then
          pause
          continue
        fi
        rm -rf "$TEMPLATE_ROOT"
        if [ -f /opt/rebecca/.env ]; then
          sed -i '/^CUSTOM_TEMPLATES_DIRECTORY=/d;/^SUBSCRIPTION_PAGE_TEMPLATE=/d' /opt/rebecca/.env 2>/dev/null || true
        fi
        ok 'BaToHub template changes removed'
        pause
        ;;
      6) template_remove;;
      7)
        header
        printf '%s\n' 'BaToHub logs - Rebecca entries'
        if [ -f "$LOG_FILE" ]; then
          grep -iE 'rebecca|ssl|template|certbot|letsencrypt' "$LOG_FILE" 2>/dev/null | tail -n 120 || true
        else
          err "Log file not found: $LOG_FILE"
        fi
        pause
        ;;
      0) return;;
    esac
  done
}

license_menu() {
  while :; do
    header
    printf '%s\n' '1) Re-validate license' '2) License status' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1)
        rm -f "$LICENSE_KEY_FILE"
        ensure_license
        pause
        ;;
      2)
        if [ -f "$LICENSE_FILE" ]; then
          cat "$LICENSE_FILE"
        else
          err 'No local license receipt.'
        fi
        pause
        ;;
      0) return;;
    esac
  done
}

settings_menu() {
  header
  if [ -f "${CONFIG_DIR}/batohub.conf" ]; then
    cat "${CONFIG_DIR}/batohub.conf"
  else
    err "Configuration file not found: ${CONFIG_DIR}/batohub.conf"
  fi
  pause
}

logs_menu() {
  header
  if [ -f "$LOG_FILE" ]; then
    tail -n 120 "$LOG_FILE"
  else
    err "Log file not found: $LOG_FILE"
  fi
  pause
}

repair_menu() {
  header
  install -d -m 750 "${CONFIG_DIR}" "${STATE_DIR}" "${LOG_DIR}"
  chmod 700 "${CONFIG_DIR}" 2>/dev/null || true
  ok "BaToHub directories repaired"
  pause
}

uninstall_menu() {
  header
  if ! confirm_destructive 'Remove BaToHub from this server?'; then
    pause
    return
  fi
  /opt/batohub/bin/uninstall
}

main_menu() {
  ensure_license || exit 1
  while :; do
    header
    printf '%s\n' '1) Update' '2) Server' '3) Tools' '4) License' '5) Settings' '6) Logs' '7) Repair' '8) Uninstall' '0) Exit'
    read -r -p 'Selection: ' c
    case "$c" in
      1) update_all;;
      2) server_menu;;
      3) tools_menu;;
      4) license_menu;;
      5) settings_menu;;
      6) logs_menu;;
      7) repair_menu;;
      8) uninstall_menu;;
      0) return;;
    esac
  done
}

main_menu
