#!/usr/bin/env bash
set -Eeuo pipefail

# Backup delivery to Telegram.
#
# BaToHub creates a backup, verifies that the archive exists and is not empty,
# sends it through the Bot API, and records the message that carried it. The
# delivery is only reported as successful when the API answered with ok=true; a
# failed or empty backup is never sent.
#
# Retention has two parts. Locally the usual backup retention applies. On
# Telegram the Bot API only allows a bot to delete a message it sent within 48
# hours, so BaToHub removes the messages it is allowed to remove and reports the
# ones the API refuses instead of claiming they were removed.

BACKUP_DELIVERY_LEDGER_NAME="telegram-delivered"

backup_delivery_ledger() { printf '%s/%s\n' "$BACKUP_DIR" "$BACKUP_DELIVERY_LEDGER_NAME"; }

backup_delivery_record() {
  local archive="$1" message_id="$2" ledger
  ledger="$(backup_delivery_ledger)"
  install -d -m 0750 -o root -g root "$BACKUP_DIR"
  printf '%s\t%s\t%s\n' "$(basename "$archive")" "${message_id:-unknown}" "$(date '+%F %T')" >>"$ledger"
  harden_file "$ledger" 0600
  return 0
}

backup_delivery_ledger_lines() {
  local ledger
  ledger="$(backup_delivery_ledger)"
  [[ -r "$ledger" ]] || return 0
  cat "$ledger"
  return 0
}

# Removes the messages the Bot API still allows a bot to remove. The messages it
# refuses are reported, because after 48 hours they have to be removed by the
# operator.
backup_delivery_prune_remote() {
  local keep="$1" count=0 name message stamp chat removed=0 failed=0
  local -a names=() messages=() stamps=()
  chat="$(telegram_chat_id)" || return 1
  while IFS=$'\t' read -r name message stamp; do
    [[ -n "$name" ]] || continue
    names+=("$name")
    messages+=("$message")
    stamps+=("$stamp")
  done < <(backup_delivery_ledger_lines)
  count="${#names[@]}"
  if [[ "$count" -le "$keep" ]]; then
    printf 'Delivered backups on record: %s (limit %s). Nothing to remove.\n' "$count" "$keep"
    return 0
  fi
  local index
  for ((index = 0; index < count - keep; index++)); do
    message="${messages[index]}"
    if [[ -z "$message" || "$message" == "unknown" ]]; then
      failed=$((failed + 1))
      continue
    fi
    if telegram_call deleteMessage --form "chat_id=${chat}" --form "message_id=${message}" >/dev/null 2>&1; then
      removed=$((removed + 1))
    else
      failed=$((failed + 1))
    fi
  done
  printf 'Removed on Telegram: %s. The API refused: %s.\n' "$removed" "$failed"
  if [[ "$failed" -gt 0 ]]; then
    warn "The Bot API only lets a bot delete a message it sent within 48 hours."
    warn "Older messages stay in the chat and have to be removed by hand."
  fi
  if [[ "$removed" -gt 0 ]]; then
    local tmp
    tmp="$(mktemp_file ledger)"
    tail -n "$keep" "$(backup_delivery_ledger)" >"$tmp" 2>/dev/null || : >"$tmp"
    chmod 0600 "$tmp"
    mv -f -- "$tmp" "$(backup_delivery_ledger)"
    harden_file "$(backup_delivery_ledger)" 0600
  fi
  return 0
}

backup_delivery_status() {
  local schedule enabled token_state chat
  schedule="$(telegram_config_value TELEGRAM_BACKUP_SCHEDULE daily)"
  enabled="$(telegram_config_value TELEGRAM_BACKUP_ENABLED 0)"
  chat="$(telegram_config_value TELEGRAM_CHAT_ID "")"
  if telegram_token_configured; then
    token_state="configured"
  else
    token_state="not configured"
  fi
  printf 'Configuration file: %s\n' "$TELEGRAM_CONF"
  printf 'Bot token: %s\n' "$token_state"
  printf 'Chat id: %s\n' "${chat:-not configured}"
  printf 'Delivery: %s\n' "$([[ "$enabled" == "1" ]] && printf enabled || printf disabled)"
  printf 'Schedule: %s\n' "$schedule"
  printf 'Local backup retention: %s archives\n' "$BACKUP_KEEP"
  printf 'Remote retention: %s backups\n' "$(telegram_config_value TELEGRAM_BACKUP_KEEP_REMOTE 7)"
  printf 'Upload limit: %s bytes per message\n' "$(telegram_config_value TELEGRAM_MAX_UPLOAD_BYTES "$TELEGRAM_MAX_UPLOAD_BYTES")"
  timer_status_line backup || true
  return 0
}

backup_delivery_configure_flow() {
  local token chat schedule keep answer
  need_root || return 1
  telegram_config_ensure || return 1
  ui_title "Telegram delivery configuration"
  printf 'The token and the chat id are stored in %s with mode 0600, owner root.\n' "$TELEGRAM_CONF"
  printf 'They are never printed and never written to a log.\n\n'
  answer="$(trim "$(ui_prompt 'Change the bot token? [y/N] ' '')")"
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    token="$(trim "$(ui_prompt 'Bot token: ' '')")"
    if [[ -z "$token" ]]; then
      warn "No token was entered; the stored token was kept."
    else
      telegram_config_set TELEGRAM_BOT_TOKEN "$token" || return 1
      ok "The bot token was stored."
    fi
  fi
  chat="$(trim "$(ui_prompt "Chat id [$(telegram_config_value TELEGRAM_CHAT_ID '')]: " '')")"
  if [[ -n "$chat" ]]; then
    telegram_config_set TELEGRAM_CHAT_ID "$chat" || return 1
  fi
  schedule="$(trim "$(ui_prompt "Schedule (hourly, daily, weekly) [$(telegram_config_value TELEGRAM_BACKUP_SCHEDULE daily)]: " '')")"
  if [[ -n "$schedule" ]]; then
    timer_oncalendar "$schedule" >/dev/null || {
      err "Unknown schedule: ${schedule}"
      return 1
    }
    telegram_config_set TELEGRAM_BACKUP_SCHEDULE "$schedule" || return 1
  fi
  keep="$(trim "$(ui_prompt "Remote retention (backups kept on Telegram) [$(telegram_config_value TELEGRAM_BACKUP_KEEP_REMOTE 7)]: " '')")"
  if [[ -n "$keep" ]]; then
    [[ "$keep" =~ ^[0-9]+$ ]] || {
      err "The remote retention must be a number."
      return 1
    }
    telegram_config_set TELEGRAM_BACKUP_KEEP_REMOTE "$keep" || return 1
  fi
  ok "The configuration was written."
  return 0
}

backup_delivery_test_flow() {
  need_root || return 1
  ui_title "Test the Telegram connection"
  printf 'A short message is sent to the configured chat. No backup is created.\n\n'
  if ! ui_confirm 'Send the test message?'; then
    printf 'Nothing was sent.\n'
    return 0
  fi
  if ! telegram_send_message "BaToHub delivery test from $(hostname 2>/dev/null || printf unknown)"; then
    return 1
  fi
  ok "The Telegram API accepted the message."
  return 0
}

# Creates a backup and delivers it. Used both by the menu and by the scheduled
# task, so the scheduled path performs exactly the steps the operator can run by
# hand.
backup_delivery_run() {
  local archive panel message_id keep
  need_root || return 1
  telegram_token_configured || {
    err "No Telegram bot token is configured."
    return 1
  }
  panel="$(panel_config_name)"
  printf 'Creating a backup...\n'
  archive="$(backup_create "$panel")" || {
    err "The backup could not be created, so nothing was sent."
    return 1
  }
  printf 'Backup: %s\n' "$archive"
  telegram_send_archive "$archive" "BaToHub backup" || {
    err "The backup was created but could not be delivered."
    err "Archive: ${archive}"
    return 1
  }
  message_id="$(printf '%s' "$API_BODY" | api_json_value result.message_id 2>/dev/null || true)"
  backup_delivery_record "$archive" "$message_id"
  keep="$(telegram_config_value TELEGRAM_BACKUP_KEEP_REMOTE 7)"
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=7
  backup_delivery_prune_remote "$keep" || true
  return 0
}

backup_delivery_send_latest_flow() {
  local archive answer
  need_root || return 1
  ui_title "Send an existing backup"
  backup_list || true
  archive="$(trim "$(ui_prompt '\nPath of the archive to send: ' '')")"
  if [[ -z "$archive" || ! -r "$archive" ]]; then
    err "The archive is not readable: ${archive:-none}"
    return 1
  fi
  if ! ui_confirm "Send ${archive} to the configured Telegram chat?"; then
    printf 'Nothing was sent.\n'
    return 0
  fi
  telegram_send_archive "$archive" "BaToHub backup" || return 1
  return 0
}

backup_delivery_enable_flow() {
  local schedule
  need_root || return 1
  schedule="$(telegram_config_value TELEGRAM_BACKUP_SCHEDULE daily)"
  ui_title "Enable or disable the schedule"
  timer_oncalendar "$schedule" >/dev/null || schedule="daily"
  printf '1) Enable the delivery schedule (%s)\n' "$schedule"
  printf '2) Disable it\n'
  printf '0) Back\n'
  case "$(ui_menu_choice)" in
  1)
    telegram_token_configured || {
      err "Configure the bot token first."
      return 1
    }
    telegram_chat_id >/dev/null || {
      err "Configure the chat id first."
      return 1
    }
    if ! timer_install backup "$schedule" "${GLOBAL_CMD_NAME} --backup-deliver"; then
      return 1
    fi
    telegram_config_set TELEGRAM_BACKUP_ENABLED 1 || return 1
    ok "The delivery schedule is enabled."
    ;;
  2)
    timer_remove backup || true
    telegram_config_set TELEGRAM_BACKUP_ENABLED 0 || return 1
    ok "The delivery schedule is disabled."
    ;;
  *) return 0 ;;
  esac
  return 0
}

backup_delivery_menu() {
  local choice
  while true; do
    ui_title "Backup delivery"
    backup_delivery_status
    printf '\n'
    printf '1) Configure the token, chat id, schedule and retention\n'
    printf '2) Send a test message\n'
    printf '3) Back up now and deliver\n'
    printf '4) Send an existing backup\n'
    printf '5) Enable or disable the schedule\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      backup_delivery_configure_flow || true
      pause
      ;;
    2)
      backup_delivery_test_flow || true
      pause
      ;;
    3)
      backup_delivery_run || true
      pause
      ;;
    4)
      backup_delivery_send_latest_flow || true
      pause
      ;;
    5)
      backup_delivery_enable_flow || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

backup_delivery_cli() {
  local command="${1:-}"
  case "$command" in
  status) backup_delivery_status ;;
  test)
    need_root || return 1
    telegram_send_message "BaToHub delivery test from $(hostname 2>/dev/null || printf unknown)" || return 1
    ok "A test message was delivered to the configured chat."
    ;;
  send) backup_delivery_run ;;
  ledger) backup_delivery_ledger_lines ;;
  *)
    err "Unknown backup-deliver command: ${command:-<none>}"
    printf 'Backup delivery commands: status, test, send, ledger\n'
    return 2
    ;;
  esac
}
