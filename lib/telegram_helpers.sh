#!/usr/bin/env bash
set -Eeuo pipefail

# Telegram Bot API client.
#
# One client is shared by the backup delivery and by the management bot. Two
# properties are enforced here:
#
#   1. The bot token is part of the request path of every Bot API call. It is
#      written into the curl configuration file by the HTTP layer instead of
#      being passed as an argument, so it never appears in the process list; it
#      is also never written to a log or to an error message.
#   2. The optional shell file below is the only place a token is stored on disk,
#      and it is kept at mode 0600, owner root.

TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
TELEGRAM_API_BASE="${TELEGRAM_API_BASE:-https://api.telegram.org}"
# The Bot API refuses an upload larger than 50 MB, so a backup is split before it
# is sent and the default limit stays below that figure.
TELEGRAM_MAX_UPLOAD_BYTES="${TELEGRAM_MAX_UPLOAD_BYTES:-45000000}"

telegram_config_ensure() {
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  if [[ ! -f "$TELEGRAM_CONF" ]]; then
    atomic_write "$TELEGRAM_CONF" 0600 "# Telegram delivery configuration for BaToHub.
# Fill in the bot token and the chat id, then enable the features you want.
# This file holds a credential and is kept at mode 0600, owner root:root.
TELEGRAM_BOT_TOKEN=\"\"
TELEGRAM_CHAT_ID=\"\"
TELEGRAM_BACKUP_ENABLED=\"0\"
TELEGRAM_BACKUP_SCHEDULE=\"daily\"
TELEGRAM_BACKUP_KEEP_REMOTE=\"7\"
TELEGRAM_MAX_UPLOAD_BYTES=\"${TELEGRAM_MAX_UPLOAD_BYTES}\"
"
  fi
  harden_file "$TELEGRAM_CONF" 0600
  return 0
}

telegram_config_value() {
  local key="$1" fallback="${2:-}"
  local value=""
  if [[ -r "$TELEGRAM_CONF" ]]; then
    value="$(read_env_value "$TELEGRAM_CONF" "$key" 2>/dev/null || true)"
  fi
  printf '%s\n' "${value:-$fallback}"
}

telegram_config_set() {
  local key="$1" value="$2"
  telegram_config_ensure || return 1
  valid_env_key "$key" || {
    err "Invalid configuration key: $key"
    return 1
  }
  set_env_value "$TELEGRAM_CONF" "$key" "$value" || return 1
  harden_file "$TELEGRAM_CONF" 0600
  return 0
}

telegram_token() {
  local token
  token="$(trim "$(telegram_config_value TELEGRAM_BOT_TOKEN "")")"
  [[ -n "$token" ]] || {
    err "No Telegram bot token is configured."
    err "Set TELEGRAM_BOT_TOKEN in ${TELEGRAM_CONF}."
    return 1
  }
  printf '%s\n' "$token"
}

telegram_chat_id() {
  local chat
  chat="$(trim "$(telegram_config_value TELEGRAM_CHAT_ID "")")"
  [[ -n "$chat" ]] || {
    err "No Telegram chat id is configured."
    err "Set TELEGRAM_CHAT_ID in ${TELEGRAM_CONF}."
    return 1
  }
  printf '%s\n' "$chat"
}

telegram_token_configured() { [[ -n "$(trim "$(telegram_config_value TELEGRAM_BOT_TOKEN "")")" ]]; }

# telegram_call METHOD [--form VALUE]...
#
# API_BODY holds the response and the function fails when the Bot API answers
# with ok=false or when the transport failed. The token is never printed.
telegram_call() {
  local method="${1:-}"
  shift || true
  local token url
  [[ -n "$method" ]] || {
    err "A Telegram API method is required."
    return 2
  }
  token="$(telegram_token)" || return 1
  url="${TELEGRAM_API_BASE}/bot${token}/${method}"
  local -a args=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --form)
      args+=(--form "${2:-}")
      shift 2
      ;;
    *)
      err "telegram_call: unknown argument: $1"
      return 2
      ;;
    esac
  done
  local timeout="${API_TIMEOUT:-30}"
  API_TIMEOUT="$timeout" api_request POST "" --private-url "$url" "${args[@]+"${args[@]}"}" || {
    err "The Telegram API request ${method} did not complete."
    return 1
  }
  if [[ ! "${API_STATUS:-}" =~ ^2[0-9]{2}$ ]]; then
    local description
    description="$(printf '%s' "${API_BODY:-}" | api_json_value description 2>/dev/null || true)"
    err "The Telegram API answered with status ${API_STATUS}: ${description:-no description}"
    log "TELEGRAM method=${method} status=${API_STATUS}"
    return 1
  fi
  local ok
  ok="$(printf '%s' "${API_BODY:-}" | api_json_value ok 2>/dev/null || true)"
  if [[ "$ok" != "true" ]]; then
    err "The Telegram API refused ${method}: $(printf '%s' "${API_BODY:-}" | api_json_value description 2>/dev/null || printf 'no description')"
    log "TELEGRAM method=${method} refused"
    return 1
  fi
  return 0
}

telegram_get_me() {
  telegram_call getMe || return 1
  printf '%s' "$API_BODY" | api_json_value result.username 2>/dev/null || true
  printf '\n'
}

# telegram_send_message TEXT [CHAT_ID]
#
# The chat defaults to the configured delivery chat; the bot passes the chat that
# sent the command so a reply goes back to its sender.
telegram_send_message() {
  local text="$1" chat="${2:-}"
  if [[ -z "$chat" ]]; then
    chat="$(telegram_chat_id)" || return 1
  fi
  telegram_call sendMessage --form "chat_id=${chat}" --form "text=${text}"
}

telegram_send_document() {
  local file="$1" caption="${2:-}" chat
  local -a args=()
  [[ -r "$file" ]] || {
    err "File to send is not readable: $file"
    return 1
  }
  [[ -s "$file" ]] || {
    err "Refusing to send an empty file: $file"
    return 1
  }
  chat="$(telegram_chat_id)" || return 1
  args=(--form "chat_id=${chat}" --form "document=@${file}")
  [[ -n "$caption" ]] && args+=(--form "caption=${caption}")
  API_TIMEOUT="${TELEGRAM_UPLOAD_TIMEOUT:-600}" telegram_call sendDocument "${args[@]}"
}

# Sends an archive, splitting it when the Bot API would refuse the size. Every
# part is a plain byte range of the original file, so the receiver can restore
# the archive by concatenating the parts in order; the caption states the part
# number and the total.
telegram_send_archive() {
  local archive="$1" label="${2:-BaToHub backup}" size max parts dir part count=0 total
  [[ -r "$archive" ]] || {
    err "Archive is not readable: $archive"
    return 1
  }
  [[ -s "$archive" ]] || {
    err "The archive is empty, so nothing was sent: $archive"
    return 1
  }
  size="$(stat -c '%s' "$archive")"
  max="$(telegram_config_value TELEGRAM_MAX_UPLOAD_BYTES "$TELEGRAM_MAX_UPLOAD_BYTES")"
  [[ "$max" =~ ^[0-9]+$ ]] || max="$TELEGRAM_MAX_UPLOAD_BYTES"

  if [[ "$size" -le "$max" ]]; then
    if ! telegram_send_document "$archive" "${label}: $(basename "$archive")"; then
      return 1
    fi
    log "TELEGRAM backup sent name=$(basename "$archive") bytes=${size}"
    ok "Backup delivered to Telegram: $(basename "$archive")"
    return 0
  fi

  need_cmd split || {
    err "The archive is larger than the Telegram limit and the split command is not available."
    return 1
  }
  dir="$(mktemp_dir telegram)"
  split -b "$max" -d --suffix-length=2 "$archive" "${dir}/part."
  parts=()
  while IFS= read -r part; do
    [[ -n "$part" ]] && parts+=("$part")
  done < <(find "$dir" -maxdepth 1 -type f -name 'part.*' | sort)
  total="${#parts[@]}"
  if [[ "$total" -eq 0 ]]; then
    rm -rf -- "$dir"
    err "The archive could not be split."
    return 1
  fi
  warn "The archive is larger than the Telegram upload limit and was split into ${total} parts."
  warn "Restore it by concatenating the parts in order, then extracting the result."
  for part in "${parts[@]}"; do
    count=$((count + 1))
    if ! telegram_send_document "$part" "${label} part ${count}/${total} of $(basename "$archive")"; then
      rm -rf -- "$dir"
      err "Part ${count} of ${total} could not be delivered."
      return 1
    fi
  done
  rm -rf -- "$dir"
  log "TELEGRAM backup sent name=$(basename "$archive") bytes=${size} parts=${total}"
  ok "Backup delivered to Telegram in ${total} parts."
  return 0
}

# Verifies a delivery by asking the Bot API for the message that was sent. A
# delivery is only reported as successful when the API confirms it.
telegram_message_exists() {
  local message_id="$1" chat
  [[ -n "$message_id" ]] || return 1
  chat="$(telegram_chat_id)" || return 1
  telegram_call forwardMessage --form "chat_id=${chat}" --form "from_chat_id=${chat}" \
    --form "message_id=${message_id}" >/dev/null 2>&1 || return 1
  return 0
}
