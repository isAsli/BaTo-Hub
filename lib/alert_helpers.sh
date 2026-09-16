#!/usr/bin/env bash
set -Eeuo pipefail

# Alerts.
#
# Each alert has a name, an enabled flag, a threshold and a cooldown. The checks
# read the state BaToHub already keeps, so no agent and no telemetry is involved.
# Delivery goes to Telegram, to an SMTP recipient, or to a webhook, and every
# credential involved is read from ${CONFIG_DIR}/alerts.conf, which is kept at
# mode 0600 and is never printed.
#
# A cooldown file per alert records when it was last delivered, so a continuing
# condition is not reported on every run.

ALERT_CONF="${CONFIG_DIR}/alerts.conf"
ALERT_LOG="${LOG_DIR}/alerts.log"
ALERT_STATE_DIR="${STATE_DIR}/alerts"

# The alert names, their default thresholds and whether they are enabled by
# default. A threshold of -1 means the alert has no numeric threshold.
ALERT_TYPES=(
  panel_down
  node_offline
  ssl_expiring
  version_outdated
  disk_usage
  memory_usage
  cpu_load
  backup_stale
  update_failed
)

alert_default_threshold() {
  case "${1:-}" in
  ssl_expiring) printf '14\n' ;;
  version_outdated) printf '0\n' ;;
  disk_usage) printf '85\n' ;;
  memory_usage) printf '90\n' ;;
  cpu_load) printf '4\n' ;;
  backup_stale) printf '48\n' ;;
  *) printf '0\n' ;;
  esac
}

alert_default_cooldown() {
  case "${1:-}" in
  cpu_load | memory_usage) printf '900\n' ;;
  *) printf '3600\n' ;;
  esac
}

alert_config_ensure() {
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  if [[ ! -f "$ALERT_CONF" ]]; then
    local content="# Alert configuration for BaToHub.
# Each alert has an enabled flag, a threshold and a cooldown in seconds.
# No alert is enabled here: nothing is delivered until an operator turns one on.
# Delivery credentials are kept here as well; this file is mode 0600, owner root.
"
    local name
    for name in "${ALERT_TYPES[@]}"; do
      content+="$(printf 'ALERT_%s=\"0\"\nALERT_%s_THRESHOLD=\"%s\"\nALERT_%s_COOLDOWN=\"%s\"\n' \
        "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" \
        "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" "$(alert_default_threshold "$name")" \
        "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" "$(alert_default_cooldown "$name")")"
    done
    content+='SMTP_HOST=""
SMTP_PORT="587"
SMTP_USER=""
SMTP_PASSWORD=""
SMTP_FROM=""
SMTP_TO=""
ALERT_WEBHOOK_URL=""
'
    atomic_write "$ALERT_CONF" 0600 "$content"
  fi
  harden_file "$ALERT_CONF" 0600
  return 0
}

alert_config_value() {
  local key="$1" fallback="${2:-}"
  local value=""
  if [[ -r "$ALERT_CONF" ]]; then
    value="$(read_env_value "$ALERT_CONF" "$key" 2>/dev/null || true)"
  fi
  printf '%s\n' "${value:-$fallback}"
}

alert_config_set() {
  local key="$1" value="$2"
  alert_config_ensure || return 1
  valid_env_key "$key" || {
    err "Invalid configuration key: $key"
    return 1
  }
  set_env_value "$ALERT_CONF" "$key" "$value" || return 1
  harden_file "$ALERT_CONF" 0600
  return 0
}

alert_upper() { printf '%s\n' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; }

# An alert that has no entry in the configuration file is off. This is what keeps
# an alert added by a later release from starting to deliver on its own: it stays
# silent until an operator enables it here.
alert_enabled() {
  local name
  name="$(alert_upper "$1")"
  [[ "$(trim "$(alert_config_value "ALERT_${name}" 0)")" == "1" ]]
}

alert_threshold() {
  local name
  name="$(alert_upper "$1")"
  trim "$(alert_config_value "ALERT_${name}_THRESHOLD" "$(alert_default_threshold "$1")")"
}

alert_cooldown() {
  local name
  name="$(alert_upper "$1")"
  trim "$(alert_config_value "ALERT_${name}_COOLDOWN" "$(alert_default_cooldown "$1")")"
}

alert_log() {
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*" >>"$ALERT_LOG" 2>/dev/null || true
  log "ALERT $*"
}

alert_cooldown_file() { printf '%s/%s.last\n' "$ALERT_STATE_DIR" "$1"; }

# True when the alert may be delivered now: either it was never delivered, or the
# cooldown has elapsed.
alert_may_deliver() {
  local name="$1" cooldown file last now
  cooldown="$(alert_cooldown "$name")"
  [[ "$cooldown" =~ ^[0-9]+$ ]] || cooldown=3600
  file="$(alert_cooldown_file "$name")"
  [[ -r "$file" ]] || return 0
  last="$(head -n 1 "$file" | tr -dc '0-9')"
  [[ -n "$last" ]] || return 0
  now="$(date +%s)"
  [[ $((now - last)) -ge "$cooldown" ]]
}

alert_mark_delivered() {
  local name="$1" file
  install -d -m 0750 -o root -g root "$ALERT_STATE_DIR"
  file="$(alert_cooldown_file "$name")"
  printf '%s\n' "$(date +%s)" >"$file"
  harden_file "$file" 0640
  return 0
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

alert_check_panel_down() {
  local panel state
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    panel_detect_state "$panel" || continue
    state="$(panel_state_of "$panel")"
    [[ "$state" == "running" ]] && continue
    printf '%s\t%s is %s\n' panel_down "$(panel_display_for "$panel")" "$(panel_status_text "$state")"
  done < <(loader_panels)
  return 0
}

alert_check_node_offline() {
  local panel name state
  while IFS=$'\t' read -r panel name; do
    [[ -n "$panel" ]] || continue
    state="$(node_status_line "$panel" "$name")"
    case "$state" in
    running | connected | online) continue ;;
    esac
    printf '%s\tnode %s of %s reports %s\n' node_offline "$name" "$panel" "${state:-unknown}"
  done < <(node_records "")
  return 0
}

alert_check_ssl_expiring() {
  local panel name cert days threshold
  threshold="$(alert_threshold ssl_expiring)"
  [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=14
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    while IFS=' ' read -r name _ _ _ _; do
      [[ -n "$name" ]] || continue
      cert="${STATE_DIR}/panels/${panel}/ssl/$(ssl_target_slug "$name")/fullchain.pem"
      [[ -s "$cert" ]] || continue
      days="$(ssl_days_remaining "$cert" 2>/dev/null || true)"
      [[ -n "$days" ]] || continue
      [[ "$days" -le "$threshold" ]] || continue
      printf '%s\tcertificate of %s for %s expires in %s days\n' ssl_expiring "$name" "$panel" "$days"
    done < <(ssl_domains_list "$panel")
  done < <(loader_panels)
  return 0
}

alert_disk_used_percent() {
  local path="${1:-/}"
  df -P "$path" 2>/dev/null | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

alert_memory_used_percent() {
  free 2>/dev/null | awk '/^Mem:/ { if ($2 > 0) printf "%d\n", ($3 / $2) * 100 }'
}

alert_load_per_cpu() {
  local load cpus
  load="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || printf '')"
  cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
  [[ -n "$load" && "$cpus" =~ ^[0-9]+$ && "$cpus" -gt 0 ]] || return 1
  awk -v load="$load" -v cpus="$cpus" 'BEGIN { printf "%.4f\n", load / cpus }'
}

# A panel whose installed version differs from the newest stable release the
# panel publishes is reported. The installed version is read from the panel
# itself; the published one comes from the panel's own repository, which is the
# only outbound request any alert makes, and a panel whose repository cannot be
# read is reported as unknown rather than as outdated.
alert_check_version_outdated() {
  local panel installed latest
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    installed="$(panel_version_of "$panel")"
    [[ -n "$installed" && "$installed" != "unknown" ]] || continue
    panel_load "$panel" >/dev/null 2>&1 || continue
    latest="$(panel_latest_stable_version 2>/dev/null || true)"
    [[ -n "$latest" ]] || continue
    [[ "${installed#v}" == "${latest#v}" ]] && continue
    printf '%s\t%s runs %s and %s is published\n' version_outdated \
      "$(panel_display_for "$panel")" "$installed" "$latest"
  done < <(loader_panels)
  return 0
}

alert_check_disk_usage() {
  local threshold used path
  threshold="$(alert_threshold disk_usage)"
  [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=85
  for path in / /var /opt; do
    [[ -d "$path" ]] || continue
    used="$(alert_disk_used_percent "$path")"
    [[ -n "$used" ]] || continue
    [[ "$used" -ge "$threshold" ]] || continue
    printf '%s\tdisk usage of %s is %s%% (threshold %s%%)\n' disk_usage "$path" "$used" "$threshold"
  done
  return 0
}

alert_check_memory_usage() {
  local threshold used
  threshold="$(alert_threshold memory_usage)"
  [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=90
  used="$(alert_memory_used_percent)"
  [[ -n "$used" ]] || return 0
  [[ "$used" -ge "$threshold" ]] || return 0
  printf '%s\tmemory usage is %s%% (threshold %s%%)\n' memory_usage "$used" "$threshold"
  return 0
}

alert_check_cpu_load() {
  local threshold load
  threshold="$(alert_threshold cpu_load)"
  [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=4
  load="$(alert_load_per_cpu)" || return 0
  awk -v load="$load" -v threshold="$threshold" 'BEGIN { if (load < threshold) exit 1 }' || return 0
  printf '%s\tload per processor is %s (threshold %s)\n' cpu_load "$load" "$threshold"
  return 0
}

# A backup is stale when the newest archive is older than the configured number
# of hours, which covers both a missing schedule and a backup that stopped
# working. It never claims anything about a specific failed run.
alert_check_backup_stale() {
  local threshold hours newest now
  threshold="$(alert_threshold backup_stale)"
  [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=48
  if [[ ! -d "$BACKUP_DIR" ]]; then
    printf '%s\tno backup directory exists at %s\n' backup_stale "$BACKUP_DIR"
    return 0
  fi
  newest="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%T@\n' 2>/dev/null | sort -n | tail -n 1)"
  if [[ -z "$newest" ]]; then
    printf '%s\tno backup archive exists in %s\n' backup_stale "$BACKUP_DIR"
    return 0
  fi
  now="$(date +%s)"
  hours=$(((now - ${newest%%.*}) / 3600))
  [[ "$hours" -ge "$threshold" ]] || return 0
  printf '%s\tthe newest backup is %s hours old (threshold %s hours)\n' backup_stale "$hours" "$threshold"
  return 0
}

# The update log records every outcome. A failure is reported when the most
# recent outcome line it holds is a failure.
alert_check_update_failed() {
  local log="${LOG_DIR}/update.log" last
  [[ -r "$log" ]] || return 0
  last="$(grep -E 'update completed|update aborted|rolling back|post-update verification failed|no update needed|downgrade refused' "$log" |
    tail -n 1 || true)"
  [[ -n "$last" ]] || return 0
  case "$last" in
  *"update completed"* | *"no update needed"* | *"downgrade refused"*) return 0 ;;
  esac
  printf '%s\tthe most recent recorded update outcome is a failure: %s\n' update_failed "$(printf '%s' "$last" | sed 's/^\[[^]]*\][[:space:]]*//')"
  return 0
}

# Runs every enabled check and prints "alert<TAB>detail" for each condition that
# currently holds.
alert_check_all() {
  local name line
  for name in "${ALERT_TYPES[@]}"; do
    alert_enabled "$name" || continue
    if declare -F "alert_check_${name}" >/dev/null 2>&1; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf '%s\n' "$line"
      done < <("alert_check_${name}" 2>/dev/null || true)
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------

alert_deliver_telegram() {
  local text="$1"
  telegram_token_configured || return 1
  telegram_send_message "$text"
}

alert_deliver_email() {
  local subject="$1" body="$2" host port user password from to message_file cfg
  host="$(trim "$(alert_config_value SMTP_HOST "")")"
  [[ -n "$host" ]] || return 1
  need_cmd curl || return 1
  port="$(trim "$(alert_config_value SMTP_PORT 587)")"
  user="$(alert_config_value SMTP_USER "")"
  password="$(alert_config_value SMTP_PASSWORD "")"
  from="$(trim "$(alert_config_value SMTP_FROM "")")"
  to="$(trim "$(alert_config_value SMTP_TO "")")"
  [[ -n "$from" && -n "$to" ]] || {
    err "SMTP_FROM and SMTP_TO are required to send an alert email."
    return 1
  }
  message_file="$(mktemp_file alert-mail)"
  {
    printf 'From: %s\n' "$from"
    printf 'To: %s\n' "$to"
    printf 'Subject: %s\n' "$subject"
    printf 'Date: %s\n' "$(date -R)"
    printf '\n%s\n' "$body"
  } >"$message_file"
  chmod 0600 "$message_file"
  cfg="$(mktemp_file alert-smtp)"
  chmod 0600 "$cfg"
  printf 'url = "smtp://%s:%s"\n' "$host" "$port" >>"$cfg"
  # The recipient and the credentials are read from the configuration file, so
  # they never appear in the process list.
  printf 'mail-from = "%s"\n' "$from" >>"$cfg"
  printf 'mail-rcpt = "%s"\n' "$to" >>"$cfg"
  printf 'upload-file = "%s"\n' "$message_file" >>"$cfg"
  [[ -n "$user" ]] && printf 'user = "%s:%s"\n' "$user" "$password" >>"$cfg"
  if [[ "$port" =~ ^(465|587|25)$ ]]; then
    printf 'ssl-reqd = "true"\n' >>"$cfg"
  fi
  if ! curl --silent --show-error --config "$cfg" >>"${LOG_FILE}" 2>&1; then
    rm -f -- "$message_file" "$cfg"
    err "Sending the alert email failed. Output: ${LOG_FILE}"
    return 1
  fi
  rm -f -- "$message_file" "$cfg"
  return 0
}

alert_deliver_webhook() {
  local alert_name="$1" detail="$2" url body
  url="$(trim "$(alert_config_value ALERT_WEBHOOK_URL "")")"
  [[ -n "$url" ]] || return 1
  case "$url" in
  https://*) ;;
  http://127.0.0.1* | http://localhost*) ;;
  *)
    err "The webhook URL must use HTTPS."
    return 1
    ;;
  esac
  body="$(json_object alert "$alert_name" detail "$detail" host "$(hostname 2>/dev/null || printf unknown)" time "$(date -u '+%FT%TZ')")"
  API_TIMEOUT="${ALERT_WEBHOOK_TIMEOUT:-15}" api_request POST "$url" \
    --header 'Content-Type: application/json' --body "$body" || {
    err "The webhook request did not complete."
    return 1
  }
  api_status_ok || {
    err "The webhook answered with status ${API_STATUS}."
    return 1
  }
  return 0
}

# Delivers one alert through every channel that is configured. The result is
# reported per channel, and a channel that is not configured is skipped rather
# than reported as a failure.
alert_deliver() {
  local name="$1" detail="$2" delivered=0 text
  text="BaToHub alert on $(hostname 2>/dev/null || printf unknown): ${name} - ${detail}"
  if telegram_token_configured; then
    if alert_deliver_telegram "$text"; then
      printf 'Telegram: delivered\n'
      delivered=1
    else
      warn "Telegram delivery failed for ${name}."
    fi
  fi
  if [[ -n "$(trim "$(alert_config_value SMTP_HOST "")")" ]]; then
    if alert_deliver_email "BaToHub alert: ${name}" "$text"; then
      printf 'Email: delivered\n'
      delivered=1
    else
      warn "Email delivery failed for ${name}."
    fi
  fi
  if [[ -n "$(trim "$(alert_config_value ALERT_WEBHOOK_URL "")")" ]]; then
    if alert_deliver_webhook "$name" "$detail"; then
      printf 'Webhook: delivered\n'
      delivered=1
    else
      warn "Webhook delivery failed for ${name}."
    fi
  fi
  if [[ "$delivered" -eq 0 ]]; then
    warn "No delivery channel is configured, so the alert was only recorded."
    alert_log "undelivered alert=${name} detail=${detail}"
    return 1
  fi
  alert_log "delivered alert=${name} detail=${detail}"
  return 0
}

# The entry point of the scheduled check.
alert_run() {
  local line name detail conditions=0 delivered=0
  while IFS=$'\t' read -r name detail; do
    [[ -n "$name" ]] || continue
    conditions=$((conditions + 1))
    if ! alert_may_deliver "$name"; then
      printf 'Suppressed by the cooldown: %s\n' "$name"
      continue
    fi
    printf '%s: %s\n' "$name" "$detail"
    if alert_deliver "$name" "$detail"; then
      alert_mark_delivered "$name"
      delivered=$((delivered + 1))
    fi
  done < <(alert_check_all)
  printf '\nConditions that currently hold: %s. Alerts delivered: %s\n' "$conditions" "$delivered"
  return 0
}
