#!/usr/bin/env bash
set -Eeuo pipefail

# The Alerts section.

alerts_status() {
  local name threshold cooldown state enabled
  printf 'Configuration file: %s\n' "$ALERT_CONF"
  printf 'Cooldown state: %s\n' "$ALERT_STATE_DIR"
  printf '\n%-16s %-9s %-11s %-10s %s\n' ALERT ENABLED THRESHOLD COOLDOWN 'LAST DELIVERED'
  for name in "${ALERT_TYPES[@]}"; do
    threshold="$(alert_threshold "$name")"
    cooldown="$(alert_cooldown "$name")"
    state="-"
    if [[ -r "$(alert_cooldown_file "$name")" ]]; then
      state="$(date -d "@$(head -n 1 "$(alert_cooldown_file "$name")" | tr -dc '0-9')" '+%F %T' 2>/dev/null || printf '-')"
    fi
    # alert_enabled reports through its exit status and prints nothing, so it is
    # asked directly instead of being read as if it returned a value.
    enabled=no
    alert_enabled "$name" && enabled=yes
    printf '%-16s %-9s %-11s %-10s %s\n' "$name" "$enabled" "$threshold" "$cooldown" "$state"
  done
  printf '\nDelivery:\n'
  printf '  Telegram token: %s\n' "$([[ -n "$(trim "$(alert_config_value TELEGRAM_BOT_TOKEN "")")" ]] && printf configured || printf 'not configured (set TELEGRAM_BOT_TOKEN in the Telegram configuration)')"
  printf '  SMTP host: %s\n' "$(trim "$(alert_config_value SMTP_HOST "")")"
  printf '  SMTP recipient: %s\n' "$(trim "$(alert_config_value SMTP_TO "")")"
  printf '  Webhook: %s\n' "$([[ -n "$(trim "$(alert_config_value ALERT_WEBHOOK_URL "")")" ]] && printf configured || printf 'not configured')"
  printf '\nSchedule:\n'
  timer_status_line alerts || true
  if [[ -r "$TELEGRAM_CONF" ]]; then
    local telegram_token
    telegram_token="$(read_env_value "$TELEGRAM_CONF" TELEGRAM_BOT_TOKEN 2>/dev/null || true)"
    printf '  Telegram configuration: %s\n' "$([[ -n "$telegram_token" ]] && printf configured || printf 'not configured')"
  fi
  return 0
}

alerts_list_flow() {
  local name
  ui_title "Alerts that currently hold"
  if ! alert_check_all | while IFS=$'\t' read -r name detail; do
    [[ -n "$name" ]] || continue
    printf '%s: %s\n' "$name" "$detail"
  done; then
    :
  fi
  printf '\nNothing is delivered by this view.\n'
  pause
}

alerts_configure_flow() {
  local choice name answer value
  need_root || return 1
  alert_config_ensure || return 1
  while true; do
    ui_title "Alert configuration"
    printf '1) Enable or disable one alert\n'
    printf '2) Change a threshold\n'
    printf '3) Change a cooldown\n'
    printf '4) Configure SMTP delivery\n'
    printf '5) Configure the webhook\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1 | 2 | 3)
      ui_title "Choose an alert"
      local index=0
      for name in "${ALERT_TYPES[@]}"; do
        index=$((index + 1))
        printf '%s) %s\n' "$index" "$name"
      done
      printf '0) Back\n'
      answer="$(ui_menu_choice)"
      [[ "$answer" =~ ^[0-9]+$ ]] || continue
      [[ "$answer" == 0 ]] && continue
      name="${ALERT_TYPES[$((answer - 1))]:-}"
      [[ -n "$name" ]] || continue
      case "$choice" in
      1)
        if ui_confirm "Enable ${name}?"; then
          alert_config_set "ALERT_$(alert_upper "$name")" 1 || continue
        else
          alert_config_set "ALERT_$(alert_upper "$name")" 0 || continue
        fi
        ok "The ${name} alert was updated."
        ;;
      2)
        value="$(trim "$(ui_prompt "Threshold for ${name} [$(alert_threshold "$name")]: " '')")"
        [[ "$value" =~ ^[0-9]+$ ]] || {
          warn "The threshold must be a number."
          continue
        }
        alert_config_set "ALERT_$(alert_upper "$name")_THRESHOLD" "$value" || continue
        ok "The threshold of ${name} is now ${value}."
        ;;
      3)
        value="$(trim "$(ui_prompt "Cooldown in seconds for ${name} [$(alert_cooldown "$name")]: " '')")"
        [[ "$value" =~ ^[0-9]+$ ]] || {
          warn "The cooldown must be a number of seconds."
          continue
        }
        alert_config_set "ALERT_$(alert_upper "$name")_COOLDOWN" "$value" || continue
        ok "The cooldown of ${name} is now ${value} seconds."
        ;;
      esac
      pause
      ;;
    4)
      ui_title "SMTP delivery"
      printf 'The password is stored in %s with mode 0600 and is never printed.\n\n' "$ALERT_CONF"
      value="$(trim "$(ui_prompt "SMTP host [$(alert_config_value SMTP_HOST '')]: " '')")"
      [[ -n "$value" ]] && alert_config_set SMTP_HOST "$value"
      value="$(trim "$(ui_prompt "SMTP port [$(alert_config_value SMTP_PORT 587)]: " '')")"
      [[ -n "$value" ]] && alert_config_set SMTP_PORT "$value"
      value="$(trim "$(ui_prompt "SMTP user [$(alert_config_value SMTP_USER '')]: " '')")"
      [[ -n "$value" ]] && alert_config_set SMTP_USER "$value"
      value="$(trim "$(ui_prompt 'SMTP password (leave empty to keep the stored one): ' '')")"
      [[ -n "$value" ]] && alert_config_set SMTP_PASSWORD "$value"
      value="$(trim "$(ui_prompt "Sender address [$(alert_config_value SMTP_FROM '')]: " '')")"
      [[ -n "$value" ]] && alert_config_set SMTP_FROM "$value"
      value="$(trim "$(ui_prompt "Recipient address [$(alert_config_value SMTP_TO '')]: " '')")"
      [[ -n "$value" ]] && alert_config_set SMTP_TO "$value"
      ok "The SMTP settings were written."
      pause
      ;;
    5)
      ui_title "Webhook delivery"
      printf 'The webhook receives a JSON object with the alert name, the detail and the time.\n\n'
      value="$(trim "$(ui_prompt "Webhook URL [$(alert_config_value ALERT_WEBHOOK_URL '')]: " '')")"
      [[ -n "$value" ]] && alert_config_set ALERT_WEBHOOK_URL "$value"
      ok "The webhook setting was written."
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

alerts_test_flow() {
  need_root || return 1
  ui_title "Test delivery"
  printf 'A test alert is delivered through every configured channel.\n'
  printf 'No check is run and no state is changed.\n\n'
  if ! ui_confirm 'Send the test delivery?'; then
    printf 'Nothing was sent.\n'
    return 0
  fi
  alert_deliver test "this is a delivery test from $(hostname 2>/dev/null || printf unknown)"
  return 0
}

alerts_schedule_flow() {
  need_root || return 1
  ui_title "Alert schedule"
  timer_status_line alerts || true
  printf '\n1) Enable the check every 15 minutes\n'
  printf '2) Disable the schedule\n'
  printf '0) Back\n'
  case "$(ui_menu_choice)" in
  1)
    timer_install alerts every15 "${GLOBAL_CMD_NAME} --alerts-run" || return 1
    ok "The alert check is scheduled."
    ;;
  2)
    timer_remove alerts || true
    ;;
  *) return 0 ;;
  esac
  return 0
}

alerts_menu() {
  local choice
  while true; do
    ui_title "Alerts"
    alerts_status
    printf '\n1) Show the alerts that currently hold\n'
    printf '2) Configure alerts and thresholds\n'
    printf '3) Test delivery\n'
    printf '4) Run the checks now and deliver\n'
    printf '5) Schedule the checks\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) alerts_list_flow ;;
    2)
      alerts_configure_flow || true
      ;;
    3)
      alerts_test_flow || true
      pause
      ;;
    4)
      ui_title "Alert run"
      alert_run || true
      pause
      ;;
    5)
      alerts_schedule_flow || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

alerts_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  status) alerts_status ;;
  check)
    alert_check_all | while IFS=$'\t' read -r name detail; do
      [[ -n "$name" ]] || continue
      printf '%s: %s\n' "$name" "$detail"
    done
    ;;
  run) alert_run ;;
  schedule)
    need_root || return 1
    timer_install alerts every15 "${GLOBAL_CMD_NAME} --alerts-run"
    ;;
  unschedule)
    need_root || return 1
    timer_remove alerts
    ;;
  enable)
    need_root || return 1
    alert_config_set "ALERT_$(alert_upper "${1:?alert name is required}")" 1
    ;;
  disable)
    need_root || return 1
    alert_config_set "ALERT_$(alert_upper "${1:?alert name is required}")" 0
    ;;
  threshold)
    need_root || return 1
    [[ "${2:-}" =~ ^[0-9]+$ ]] || {
      err "Usage: BaToHub --alerts threshold <alert> <value>"
      return 2
    }
    alert_config_set "ALERT_$(alert_upper "${1:?alert name is required}")_THRESHOLD" "$2"
    ;;
  types) printf '%s\n' "${ALERT_TYPES[@]}" ;;
  *)
    err "Unknown alerts command: ${command:-<none>}"
    printf 'Alert commands: status, check, run, schedule, unschedule, enable, disable, threshold, types\n'
    return 2
    ;;
  esac
}
