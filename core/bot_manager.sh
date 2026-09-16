#!/usr/bin/env bash
set -Eeuo pipefail

# The Telegram bot section: its configuration, its systemd service and its log.

BOT_SERVICE_NAME="batohub-bot.service"
BOT_SERVICE_PATH="/etc/systemd/system/batohub-bot.service"

bot_service_installed() { [[ -f "$BOT_SERVICE_PATH" ]]; }

bot_status() {
  printf 'Configuration file: %s\n' "$BOT_CONF"
  printf 'Command log: %s\n' "$BOT_LOG"
  if [[ -n "$(trim "$(bot_config_value TELEGRAM_BOT_TOKEN "")")" ]]; then
    printf 'Bot token: configured in the bot configuration\n'
  elif telegram_token_configured; then
    printf 'Bot token: taken from the delivery configuration\n'
  else
    printf 'Bot token: not configured\n'
  fi
  printf 'Listed users: %s\n' "$(bot_config_value TELEGRAM_BOT_USERS "" | tr ',' ' ')"
  printf 'Allowed chats: %s\n' "$(trim "$(bot_config_value TELEGRAM_BOT_CHATS "")")"
  printf 'Backup password: %s\n' \
    "$([[ -n "$(bot_config_value TELEGRAM_BOT_BACKUP_PASSWORD "")" ]] && printf configured || printf 'not configured, backups are sent unencrypted with a warning')"
  printf 'Service: %s\n' "$BOT_SERVICE_NAME"
  if bot_service_installed && systemd_available; then
    printf '  state: %s\n' "$(systemctl is-active "$BOT_SERVICE_NAME" 2>/dev/null || printf inactive)"
    printf '  enabled: %s\n' "$(systemctl is-enabled "$BOT_SERVICE_NAME" 2>/dev/null || printf disabled)"
  elif bot_service_installed; then
    printf '  unit installed; systemd is not available\n'
  else
    printf '  not installed\n'
  fi
  return 0
}

bot_service_install() {
  need_root || return 1
  if ! systemd_available; then
    err "systemd is not available, so the bot service cannot be installed."
    err "The bot can still be started by hand: ${INSTALL_DIR}/bin/batohub-bot"
    return 1
  fi
  atomic_write "$BOT_SERVICE_PATH" 0644 "$(printf '# Written by BaToHub.\n[Unit]\nDescription=BaToHub Telegram management bot\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=%s\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n' "${INSTALL_DIR}/bin/batohub-bot")"
  systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
  if ! systemctl enable --now "$BOT_SERVICE_NAME" >>"${LOG_FILE}" 2>&1; then
    err "The bot service could not be started. Inspect: systemctl status ${BOT_SERVICE_NAME}"
    return 1
  fi
  log "BOT service installed"
  ok "The bot service is installed and running."
  return 0
}

bot_service_remove() {
  need_root || return 1
  if [[ ! -f "$BOT_SERVICE_PATH" ]]; then
    warn "The bot service is not installed."
    return 1
  fi
  if systemd_available; then
    systemctl disable --now "$BOT_SERVICE_NAME" >>"${LOG_FILE}" 2>&1 || true
    systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
  fi
  rm -f -- "$BOT_SERVICE_PATH"
  log "BOT service removed"
  ok "The bot service was removed. The configuration was kept."
  return 0
}

bot_configure_flow() {
  local users chats answer
  need_root || return 1
  bot_config_ensure || return 1
  ui_title "Telegram bot configuration"
  printf 'The file is kept at mode 0600, owner root.\n'
  printf 'A user id that is not listed is refused, and a listed user id is mapped to\n'
  printf 'a BaToHub administrator account whose role then limits the commands.\n\n'
  answer="$(trim "$(ui_prompt 'Change the bot token? [y/N] ' '')")"
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    answer="$(trim "$(ui_prompt 'Bot token: ' '')")"
    if [[ -z "$answer" ]]; then
      warn "No token was entered; the stored token was kept."
    else
      bot_config_set TELEGRAM_BOT_TOKEN "$answer" || return 1
      ok "The bot token was stored."
    fi
  fi
  users="$(trim "$(ui_prompt "Users as id:account pairs, comma separated [$(bot_config_value TELEGRAM_BOT_USERS '')]: " '')")"
  if [[ -n "$users" ]]; then
    local entry id account
    local -a entries=()
    IFS=',' read -r -a entries <<<"$users"
    for entry in "${entries[@]}"; do
      entry="$(trim "$entry")"
      id="${entry%%:*}"
      account="$(trim "${entry#*:}")"
      [[ "$id" =~ ^-?[0-9]+$ ]] || {
        err "Not a Telegram user id: ${id}"
        return 1
      }
      admin_exists "$account" || {
        err "No BaToHub administrator named ${account}."
        err "Create the account first with BaToHub --admin add ${account} <role>."
        return 1
      }
    done
    bot_config_set TELEGRAM_BOT_USERS "$users" || return 1
    ok "The listed users were stored."
  fi
  chats="$(trim "$(ui_prompt "Chats the bot accepts, comma separated [$(trim "$(bot_config_value TELEGRAM_BOT_CHATS "")")]: " '')")"
  if [[ -n "$chats" ]]; then
    bot_config_set TELEGRAM_BOT_CHATS "$chats" || return 1
    ok "The allowed chats were stored."
  fi
  answer="$(trim "$(ui_prompt 'Change the backup encryption password? [y/N] ' '')")"
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    answer="$(ui_prompt 'Backup password (empty disables encryption): ' '')"
    bot_config_set TELEGRAM_BOT_BACKUP_PASSWORD "$answer" || return 1
    if [[ -n "$answer" ]]; then
      ok "Backups sent by the bot are encrypted with this password."
    else
      warn "Backups sent by the bot are not encrypted and carry a warning."
    fi
  fi
  return 0
}

bot_logs_flow() {
  ui_title "Bot log"
  if [[ -r "$BOT_LOG" ]]; then
    tail -n 60 "$BOT_LOG"
  else
    warn "The bot log does not exist yet: ${BOT_LOG}"
  fi
  pause
}

bot_once_flow() {
  need_root || return 1
  ui_title "One polling round"
  printf 'A single getUpdates request is made and the updates it returns are handled.\n'
  printf 'A reply is sent to the chat that sent the command.\n\n'
  if ! ui_confirm 'Run one polling round?'; then
    printf 'Nothing was run.\n'
    return 0
  fi
  bot_poll_once || warn "The polling round did not complete."
  return 0
}

bot_menu() {
  local choice
  while true; do
    ui_title "Telegram bot"
    bot_status
    printf '\n'
    printf '1) Configure the token, users and chats\n'
    printf '2) Install or start the bot service\n'
    printf '3) Stop and remove the bot service\n'
    printf '4) Run one polling round\n'
    printf '5) Show the command log\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      bot_configure_flow || true
      pause
      ;;
    2)
      bot_service_install || true
      pause
      ;;
    3)
      bot_service_remove || true
      pause
      ;;
    4)
      bot_once_flow || true
      pause
      ;;
    5) bot_logs_flow ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

bot_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  status) bot_status ;;
  service)
    need_root || return 1
    bot_service_install
    ;;
  remove-service)
    need_root || return 1
    bot_service_remove
    ;;
  logs)
    [[ -r "$BOT_LOG" ]] || {
      err "The bot log does not exist yet: ${BOT_LOG}"
      return 1
    }
    tail -n "${1:-60}" "$BOT_LOG"
    ;;
  once)
    bot_config_ensure || return 1
    bot_poll_once
    ;;
  users)
    bot_config_value TELEGRAM_BOT_USERS ""
    ;;
  check)
    local user_id="${1:?telegram user id is required}" chat="${2:-}"
    if bot_authorised "$user_id" "$chat"; then
      printf 'authorised %s\n' "$(bot_user_account "$user_id")"
      return 0
    fi
    printf 'refused\n'
    return 1
    ;;
  *)
    err "Unknown bot command: ${command:-<none>}"
    printf 'Bot commands: status, service, remove-service, logs, once, users, check\n'
    return 2
    ;;
  esac
}
