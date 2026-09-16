#!/usr/bin/env bash
set -Eeuo pipefail

# Telegram management bot.
#
# The bot is a separate process managed by systemd. It refuses every command from
# a chat id or user id that is not listed in its own configuration file, maps each
# listed Telegram user to a BaToHub administrator account, and then runs the
# command through the same permission gate the interactive interface uses. A
# command an account is not allowed to run is refused, not silently skipped.
#
# The bot never sends a configuration file, never sends a credential, and logs
# every command with the Telegram user id and a timestamp. A backup it sends is
# encrypted with a password the operator sets, or it carries a warning that it is
# not encrypted.

BOT_CONF="${CONFIG_DIR}/telegram_bot.conf"
BOT_LOG="${LOG_DIR}/telegram-bot.log"
BOT_OFFSET_FILE="${STATE_DIR}/telegram-bot.offset"

# The status contract of the dispatcher: 0 means the reply is the response, any
# other status is a failure, and this one means the sender was not identified, so
# no reply is sent.
BOT_STATUS_NO_REPLY=3

bot_config_ensure() {
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  if [[ ! -f "$BOT_CONF" ]]; then
    atomic_write "$BOT_CONF" 0600 "# Telegram management bot for BaToHub.
# TELEGRAM_BOT_TOKEN is the token of the bot that answers the commands.
# TELEGRAM_BOT_USERS maps a Telegram user id to a BaToHub administrator account:
#   TELEGRAM_BOT_USERS=\"123456789:admin1,987654321:admin2\"
# A user id that is not listed is refused, without a reply. TELEGRAM_BOT_CHATS
# restricts the bot to specific chats; when it is empty every chat of a listed
# user is accepted. An entry is either a chat id or the pair "user id:chat id"
# that keeps one listed user out of the chat of another.
TELEGRAM_BOT_TOKEN=\"\"
TELEGRAM_BOT_USERS=\"\"
TELEGRAM_BOT_CHATS=\"\"
TELEGRAM_BOT_BACKUP_PASSWORD=\"\"
TELEGRAM_BOT_POLL_TIMEOUT=\"25\"
"
  fi
  harden_file "$BOT_CONF" 0600
  return 0
}

bot_config_value() {
  local key="$1" fallback="${2:-}"
  local value=""
  if [[ -r "$BOT_CONF" ]]; then
    value="$(read_env_value "$BOT_CONF" "$key" 2>/dev/null || true)"
  fi
  printf '%s\n' "${value:-$fallback}"
}

bot_config_set() {
  local key="$1" value="$2"
  bot_config_ensure || return 1
  valid_env_key "$key" || {
    err "Invalid configuration key: $key"
    return 1
  }
  set_env_value "$BOT_CONF" "$key" "$value" || return 1
  harden_file "$BOT_CONF" 0600
  return 0
}

# The token of the bot. It is read from the bot configuration, and falls back to
# the delivery token so a single bot can do both jobs.
bot_token() {
  local token
  token="$(trim "$(bot_config_value TELEGRAM_BOT_TOKEN "")")"
  if [[ -z "$token" ]]; then
    telegram_token_configured || {
      err "No Telegram bot token is configured for the bot."
      err "Set TELEGRAM_BOT_TOKEN in ${BOT_CONF}."
      return 1
    }
    telegram_token >/dev/null || return 1
    printf '%s\n' "$(trim "$(telegram_config_value TELEGRAM_BOT_TOKEN "")")"
    return 0
  fi
  printf '%s\n' "$token"
}

bot_log() {
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*" >>"$BOT_LOG" 2>/dev/null || true
  log "BOT $*"
}

# The BaToHub account a Telegram user id maps to. An unlisted id yields nothing,
# and the caller refuses the command.
bot_user_account() {
  local user_id="${1:-}" entry id account
  [[ -n "$user_id" ]] || return 1
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    id="${entry%%:*}"
    account="${entry#*:}"
    if [[ "$id" == "$user_id" ]]; then
      printf '%s\n' "$(trim "$account")"
      return 0
    fi
  done < <(printf '%s\n' "$(bot_config_value TELEGRAM_BOT_USERS "")" | tr ',' '\n')
  return 1
}

# A chat is accepted when TELEGRAM_BOT_CHATS is empty, when it lists the chat id
# itself, or when it maps that chat to the sending user. The mapped form is the
# one that keeps a listed user out of the chat of another listed user.
bot_chat_allowed() {
  local user_id="${1:-}" chat_id="${2:-}" allowed entry entry_user entry_chat
  allowed="$(bot_config_value TELEGRAM_BOT_CHATS "")"
  [[ -z "$(trim "$allowed")" ]] && return 0
  while IFS= read -r entry; do
    entry="$(trim "$entry")"
    [[ -n "$entry" ]] || continue
    if [[ "$entry" == *:* ]]; then
      entry_user="${entry%%:*}"
      entry_chat="${entry#*:}"
      [[ "$entry_user" == "$user_id" && "$entry_chat" == "$chat_id" ]] && return 0
    elif [[ "$entry" == "$chat_id" ]]; then
      return 0
    fi
  done < <(printf '%s\n' "$allowed" | tr ',' '\n')
  return 1
}

bot_authorised() {
  local user_id="$1" chat_id="${2:-}" account
  if ! account="$(bot_user_account "$user_id")"; then
    bot_log "refused user=${user_id} reason=not_listed"
    return 1
  fi
  if ! bot_chat_allowed "$user_id" "$chat_id"; then
    bot_log "refused user=${user_id} chat=${chat_id} reason=chat_not_allowed"
    return 1
  fi
  if ! admin_exists "$account"; then
    bot_log "refused user=${user_id} account=${account} reason=account_missing"
    return 1
  fi
  return 0
}

bot_help_text() {
  cat <<'EOF'
Commands
/start    authenticate and show this list
/status   status of the panel BaToHub manages
/panels   list the panels and their state
/backup   create a backup and send it
/restore  list the backups; /restore <name> confirm restores one
/ssl      certificate status of the managed panel
/renew    renew the certificates of the managed panel
/users    user count and active users
/traffic  traffic summary
/alerts   recent alerts
/update   check for a BaToHub update
/restart  restart the managed panel
/logs     last lines of the panel log
/help     show this list
EOF
  return 0
}

# Every handler runs with BATOHUB_ADMIN set to the account the Telegram user maps
# to, so admin_require applies exactly as it does in the interactive interface.
bot_reply_status() {
  admin_require panels.view || return 1
  local panel
  panel="$(panel_config_name)"
  if [[ -z "$panel" ]]; then
    printf 'No panel is configured.\n'
    printf 'Run BaToHub on the server and choose one.\n'
    return 0
  fi
  printf 'Panel: %s\n' "$(panel_display_for "$panel")"
  printf 'State: %s\n' "$(panel_status_text "$(panel_state_of "$panel")")"
  printf 'Version: %s\n' "$(panel_version_of "$panel")"
  printf 'BaToHub: %s\n' "$APP_VERSION"
  return 0
}

bot_reply_panels() {
  admin_require panels.view || return 1
  local name state
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    state="$(panel_state_of "$name")"
    printf '%s: %s\n' "$(panel_display_for "$name")" "$(panel_status_text "$state")"
  done < <(loader_panels)
  return 0
}

bot_reply_backup() {
  admin_require backup.create || return 1
  local panel archive password caption encrypted=0
  panel="$(panel_config_name)"
  archive="$(backup_create "$panel")" || {
    printf 'The backup could not be created, so nothing was sent.\n'
    return 1
  }
  password="$(bot_config_value TELEGRAM_BOT_BACKUP_PASSWORD "")"
  if [[ -n "$password" ]]; then
    need_cmd gpg || {
      printf 'A backup password is configured but gpg is not installed, so the backup was not sent.\n'
      rm -f -- "$archive"
      return 1
    }
    local pass_file
    pass_file="$(mktemp_file bot-pass)"
    printf '%s' "$password" >"$pass_file"
    chmod 0600 "$pass_file"
    if ! gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase-file "$pass_file" \
      --output "${archive}.gpg" "$archive" >>"${LOG_FILE}" 2>&1; then
      rm -f -- "$pass_file"
      printf 'Encrypting the backup failed, so it was not sent.\n'
      return 1
    fi
    rm -f -- "$pass_file"
    archive="${archive}.gpg"
    encrypted=1
  fi
  caption="BaToHub backup from $(hostname 2>/dev/null || printf unknown)"
  if [[ "$encrypted" -eq 1 ]]; then
    caption="${caption} (encrypted with the configured password)"
  else
    caption="${caption} - WARNING: this archive is not encrypted. It contains configuration, which can include credentials."
  fi
  if ! telegram_send_archive "$archive" "$caption"; then
    printf 'The backup was created at %s but could not be delivered.\n' "$archive"
    return 1
  fi
  printf 'Backup delivered: %s\n' "$(basename "$archive")"
  return 0
}

bot_reply_restore() {
  admin_require backup.restore || return 1
  local argument="${1:-}" archive confirmation
  local -a files=()
  while IFS= read -r archive; do
    [[ -n "$archive" ]] && files+=("$archive")
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' 2>/dev/null | sort | tail -n 10)
  if [[ -z "$argument" ]]; then
    if [[ "${#files[@]}" -eq 0 ]]; then
      printf 'No backup archive is available.\n'
      return 0
    fi
    printf 'Backups available:\n'
    for archive in "${files[@]}"; do
      printf '  %s\n' "$(basename "$archive")"
    done
    printf '\nRestore with: /restore <name> confirm\n'
    return 0
  fi
  confirmation="$(printf '%s' "$argument" | awk '{print $NF}')"
  argument="$(printf '%s' "$argument" | sed 's/[[:space:]]*confirm[[:space:]]*$//')"
  archive="${BACKUP_DIR}/$(basename "$argument")"
  if [[ ! -r "$archive" ]]; then
    printf 'No backup archive named %s.\n' "$(basename "$argument")"
    return 1
  fi
  if [[ "$confirmation" != "confirm" ]]; then
    printf 'Restoring %s overwrites the current state.\n' "$(basename "$archive")"
    printf 'Repeat the command with the word confirm at the end to proceed.\n'
    return 0
  fi
  if ! backup_restore "$archive" "$(panel_config_name)"; then
    printf 'The restore did not complete.\n'
    return 1
  fi
  printf 'The restore completed.\n'
  return 0
}

bot_reply_ssl() {
  admin_require panels.view || return 1
  local panel
  panel="$(panel_config_name)"
  [[ -n "$panel" ]] || {
    printf 'No panel is configured.\n'
    return 0
  }
  ssl_load_panel "$panel" >/dev/null 2>&1 || {
    printf 'The SSL module of %s could not be loaded.\n' "$panel"
    return 1
  }
  local name purpose days cert
  local found=0
  while IFS=' ' read -r name purpose _ _ _; do
    [[ -n "$name" ]] || continue
    found=1
    cert="${STATE_DIR}/panels/${panel}/ssl/$(ssl_target_slug "$name")/fullchain.pem"
    days="not issued"
    [[ -s "$cert" ]] && days="expires in $(ssl_days_remaining "$cert" 2>/dev/null || printf unknown) days"
    printf '%s (%s): %s\n' "$name" "$purpose" "$days"
  done < <(ssl_domains_list "$panel")
  [[ "$found" -eq 1 ]] || printf 'No certificate name is registered for %s.\n' "$(panel_display_for "$panel")"
  return 0
}

bot_reply_renew() {
  admin_require ssl.renew || return 1
  local panel
  panel="$(panel_config_name)"
  [[ -n "$panel" ]] || {
    printf 'No panel is configured.\n'
    return 0
  }
  ssl_load_panel "$panel" >/dev/null 2>&1 || {
    printf 'The SSL module of %s could not be loaded.\n' "$panel"
    return 1
  }
  if ! ssl_renew_registered "$panel" >/dev/null 2>&1; then
    printf 'No certificate was renewed. Review the log on the server.\n'
    return 1
  fi
  printf 'Renewal finished for %s. Review the log for the per-name result.\n' "$(panel_display_for "$panel")"
  return 0
}

bot_reply_users() {
  admin_require panels.view || return 1
  local line
  line="$(report_rows active_users | tail -n +2 | grep -c . || true)"
  printf 'Active users: %s\n\n' "${line:-0}"
  report_render user_counts screen
  return 0
}

bot_reply_traffic() {
  admin_require panels.view || return 1
  report_render panel_traffic screen
  return 0
}

bot_reply_alerts() {
  admin_require alerts.view || return 1
  local line count=0
  printf 'Recent alerts:\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    count=$((count + 1))
    printf '  %s\n' "$line"
  done < <(report_rows alert_history | tail -n +2 | tail -n 10)
  [[ "$count" -gt 0 ]] || printf '  None recorded.\n'
  printf '\nConditions that currently hold:\n'
  local found=0
  while IFS=$'\t' read -r line detail; do
    [[ -n "$line" ]] || continue
    found=1
    printf '  %s: %s\n' "$line" "$detail"
  done < <(alert_check_all)
  [[ "$found" -eq 1 ]] || printf '  None.\n'
  return 0
}

bot_reply_update() {
  admin_require update.run || return 1
  local tag
  tag="$(update_release_tag 2>/dev/null)" || {
    printf 'The published release could not be resolved.\n'
    return 1
  }
  printf 'Installed: %s\n' "$APP_VERSION"
  printf 'Newest published: %s\n' "$tag"
  if [[ "${tag#v}" == "$APP_VERSION" ]]; then
    printf 'BaToHub is up to date.\n'
    return 0
  fi
  printf 'Run BaToHub --update on the server to install it.\n'
  return 0
}

bot_reply_restart() {
  admin_require panels.update || return 1
  local panel
  panel="$(panel_config_name)"
  [[ -n "$panel" ]] || {
    printf 'No panel is configured.\n'
    return 0
  }
  if ! panel_restart_safe; then
    printf 'The restart of %s failed. Review the log on the server.\n' "$(panel_display_for "$panel")"
    return 1
  fi
  printf '%s was restarted.\n' "$(panel_display_for "$panel")"
  return 0
}

bot_reply_logs() {
  admin_require panels.view || return 1
  local panel output
  panel="$(panel_config_name)"
  [[ -n "$panel" ]] || {
    printf 'No panel is configured.\n'
    return 0
  }
  panel_load "$panel" >/dev/null 2>&1 || {
    printf 'The panel could not be loaded.\n'
    return 1
  }
  output="$(panel_logs 2>/dev/null | tail -n 20 || true)"
  if [[ -z "$output" ]]; then
    printf 'No log source is available for %s.\n' "$(panel_display_for "$panel")"
    return 1
  fi
  # A log line can contain a hostname, an address or a session identifier. Only
  # the last lines are sent, and configuration files are never sent.
  printf '%s\n' "$output"
  return 0
}

# Dispatches one message. The account of the Telegram user is exported so the
# permission gate applies, and the reply is printed for the caller to deliver.
bot_dispatch() {
  local user_id="$1" chat_id="$2" text="$3" account command argument reply="" status=0
  [[ -n "$text" ]] || return 0
  if ! bot_authorised "$user_id" "$chat_id"; then
    # The refusal is logged, but nothing is sent back. A reply would confirm to
    # anyone who reaches the bot that this endpoint belongs to a BaToHub instance.
    return "$BOT_STATUS_NO_REPLY"
  fi
  account="$(bot_user_account "$user_id")"
  command="${text%% *}"
  argument="$(trim "${text#"$command"}")"
  command="$(printf '%s' "$command" | tr '[:upper:]' '[:lower:]')"
  # A command sent in a group arrives as /command@botname.
  command="${command%%@*}"
  bot_log "command user=${user_id} chat=${chat_id} account=${account} text=${command}"

  # The handlers run through the same permission gate as the interactive
  # interface, because the account of the Telegram user is the acting account.
  BATOHUB_ADMIN="$account"
  export BATOHUB_ADMIN

  case "$command" in
  /start | /help)
    printf 'BaToHub management bot\n\n'
    printf 'Account: %s (role %s)\n\n' "$account" "$(admin_current_role)"
    bot_help_text
    ;;
  /status) reply="$(bot_reply_status 2>&1)" || status=$? ;;
  /panels) reply="$(bot_reply_panels 2>&1)" || status=$? ;;
  /backup) reply="$(bot_reply_backup 2>&1)" || status=$? ;;
  /restore) reply="$(bot_reply_restore "$argument" 2>&1)" || status=$? ;;
  /ssl) reply="$(bot_reply_ssl 2>&1)" || status=$? ;;
  /renew) reply="$(bot_reply_renew 2>&1)" || status=$? ;;
  /users) reply="$(bot_reply_users 2>&1)" || status=$? ;;
  /traffic) reply="$(bot_reply_traffic 2>&1)" || status=$? ;;
  /alerts) reply="$(bot_reply_alerts 2>&1)" || status=$? ;;
  /update) reply="$(bot_reply_update 2>&1)" || status=$? ;;
  /restart) reply="$(bot_reply_restart 2>&1)" || status=$? ;;
  /logs) reply="$(bot_reply_logs 2>&1)" || status=$? ;;
  *)
    printf 'Unknown command: %s\n\n' "$command"
    bot_help_text
    ;;
  esac
  if [[ -n "$reply" ]]; then
    printf '%s\n' "$reply"
  fi
  return "$status"
}

bot_offset() {
  [[ -r "$BOT_OFFSET_FILE" ]] || {
    printf '0\n'
    return 0
  }
  printf '%s\n' "$(head -n 1 "$BOT_OFFSET_FILE" | tr -dc '0-9')"
}

bot_offset_write() {
  local offset="$1"
  install -d -m 0750 -o root -g root "$STATE_DIR"
  atomic_write "$BOT_OFFSET_FILE" 0600 "$(printf '%s\n' "$offset")"
}

# One polling round. Used by the daemon and by the verification suite, so the
# handling of an update is the same in both.
bot_poll_once() {
  local timeout offset token url text user_id chat_id update_id reply status
  timeout="$(bot_config_value TELEGRAM_BOT_POLL_TIMEOUT 25)"
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=25
  offset="$(bot_offset)"
  token="$(bot_token)" || return 1
  url="${TELEGRAM_API_BASE}/bot${token}/getUpdates?timeout=${timeout}&offset=$((offset + 1))"
  API_TIMEOUT=$((timeout + 15)) api_request GET "" --private-url "$url" || return 1
  api_status_ok || {
    err "The getUpdates request failed with status ${API_STATUS}."
    return 1
  }
  local count
  count="$(printf '%s' "$API_BODY" | api_json_count result)"
  [[ "${count:-0}" -gt 0 ]] || return 0
  while IFS=$'\t' read -r update_id user_id chat_id text; do
    [[ -n "$update_id" ]] || continue
    bot_offset_write "$update_id"
    [[ -n "$text" ]] || continue
    status=0
    reply="$(bot_dispatch "$user_id" "$chat_id" "$text")" || status=$?
    [[ "$status" -eq "$BOT_STATUS_NO_REPLY" ]] && continue
    if [[ "$status" -ne 0 ]]; then
      bot_log "refused command user=${user_id} text=${text%% *}"
      [[ -n "$reply" ]] || reply="The command was refused."
    fi
    [[ -n "$reply" ]] || continue
    telegram_send_message "$reply" "$chat_id" >/dev/null 2>&1 ||
      warn "The reply to ${user_id} could not be delivered."
  done < <(printf '%s' "$API_BODY" | python3 -c '
import json
import sys

raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except ValueError:
    raise SystemExit(2)
for update in payload.get("result", []):
    message = update.get("message") or update.get("edited_message") or {}
    text = message.get("text") or ""
    sender = message.get("from", {})
    user_id = sender.get("id", "")
    chat_id = (message.get("chat") or {}).get("id", "")
    print("%s\t%s\t%s\t%s" % (update.get("update_id", ""), user_id, chat_id, text))
')
  return 0
}

bot_run() {
  need_root || return 1
  bot_config_ensure || return 1
  printf 'BaToHub Telegram bot starting.\n'
  bot_log "started"
  while true; do
    if ! bot_poll_once; then
      warn "A polling round failed; retrying."
      bot_log "poll failed"
      sleep 5
    fi
  done
}
