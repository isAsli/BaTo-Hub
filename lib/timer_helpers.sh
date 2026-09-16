#!/usr/bin/env bash
set -Eeuo pipefail

# Scheduled jobs.
#
# A background task of BaToHub runs through a systemd timer when systemd is
# available, and through a cron file when it is not. Both are the minimum system
# wide files BaToHub needs, they are named after the task, and they are removed
# again when the task is switched off.
#
# The unit files are generated from the installation paths rather than shipped,
# because a packaged unit would carry the default paths of the release instead of
# the paths this installation actually uses.

TIMER_UNIT_DIR="/etc/systemd/system"
TIMER_CRON_DIR="/etc/cron.d"

timer_name_valid() {
  case "${1:-}" in
  "" | *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

timer_unit_name() { printf 'batohub-%s\n' "${1:?task name is required}"; }
timer_service_path() { printf '%s/%s.service\n' "$TIMER_UNIT_DIR" "$(timer_unit_name "$1")"; }
timer_timer_path() { printf '%s/%s.timer\n' "$TIMER_UNIT_DIR" "$(timer_unit_name "$1")"; }
timer_cron_path() { printf '%s/%s\n' "$TIMER_CRON_DIR" "$(timer_unit_name "$1")"; }

# OnCalendar expressions for the schedules BaToHub offers. The value is written
# from a fixed mapping, so an operator cannot inject an arbitrary unit directive
# through a schedule name.
timer_oncalendar() {
  case "${1:-}" in
  hourly) printf 'hourly\n' ;;
  daily) printf '*-*-* 03:30:00\n' ;;
  weekly) printf 'Mon *-*-* 03:30:00\n' ;;
  every15) printf '*:0/15\n' ;;
  *) return 1 ;;
  esac
}

timer_cron_expression() {
  case "${1:-}" in
  hourly) printf '0 * * * *\n' ;;
  daily) printf '30 3 * * *\n' ;;
  weekly) printf '30 3 * * 1\n' ;;
  every15) printf '*/15 * * * *\n' ;;
  *) return 1 ;;
  esac
}

timer_install() {
  local name="$1" schedule="$2" command="$3"
  local oncalendar service timer cron
  need_root || return 1
  timer_name_valid "$name" || {
    err "Invalid task name: ${name}"
    return 1
  }
  oncalendar="$(timer_oncalendar "$schedule")" || {
    err "Unknown schedule: ${schedule}. Use hourly, daily, weekly or every15."
    return 1
  }
  [[ -n "$command" ]] || {
    err "A command is required for a scheduled task."
    return 1
  }
  service="$(timer_service_path "$name")"
  timer="$(timer_timer_path "$name")"
  cron="$(timer_cron_path "$name")"

  if systemd_available; then
    atomic_write "$service" 0644 "$(printf '[Unit]\nDescription=BaToHub scheduled task %s\n\n[Service]\nType=oneshot\nExecStart=%s\n' "$name" "$command")"
    atomic_write "$timer" 0644 "$(printf '[Unit]\nDescription=BaToHub schedule for %s\n\n[Timer]\nOnCalendar=%s\nPersistent=true\nUnit=%s\n\n[Install]\nWantedBy=timers.target\n' "$name" "$oncalendar" "$(timer_unit_name "$name")")"
    rm -f -- "$cron"
    systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
    if ! systemctl enable --now "$(timer_unit_name "$name").timer" >>"${LOG_FILE}" 2>&1; then
      err "The timer could not be enabled. Inspect: systemctl status $(timer_unit_name "$name").timer"
      return 1
    fi
    log "TIMER installed name=${name} schedule=${schedule} oncalendar=${oncalendar}"
    ok "Scheduled through a systemd timer: $(timer_unit_name "$name").timer"
    return 0
  fi

  if ! need_cmd cron && ! need_cmd crond && [[ ! -d "$TIMER_CRON_DIR" ]]; then
    err "Neither systemd nor cron is available, so the schedule cannot be installed."
    return 1
  fi
  install -d -m 0755 -o root -g root "$TIMER_CRON_DIR"
  atomic_write "$cron" 0644 "$(printf 'SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n%s root %s\n' "$(timer_cron_expression "$schedule")" "$command")"
  rm -f -- "$service" "$timer"
  log "TIMER installed name=${name} schedule=${schedule} cron=${cron}"
  ok "Scheduled through cron: ${cron}"
  return 0
}

timer_remove() {
  local name="$1" service timer cron removed=0
  need_root || return 1
  timer_name_valid "$name" || return 1
  service="$(timer_service_path "$name")"
  timer="$(timer_timer_path "$name")"
  cron="$(timer_cron_path "$name")"
  if systemd_available && [[ -f "$timer" ]]; then
    systemctl disable --now "$(timer_unit_name "$name").timer" >>"${LOG_FILE}" 2>&1 || true
    systemctl daemon-reload >>"${LOG_FILE}" 2>&1 || true
    removed=1
  fi
  if [[ -e "$service" || -e "$timer" || -e "$cron" ]]; then
    rm -f -- "$service" "$timer" "$cron"
    removed=1
  fi
  if [[ "$removed" -eq 1 ]]; then
    log "TIMER removed name=${name}"
    ok "The schedule of ${name} was removed."
    return 0
  fi
  warn "No schedule named ${name} was installed."
  return 1
}

timer_status_line() {
  local name="$1" service timer cron
  service="$(timer_service_path "$name")"
  timer="$(timer_timer_path "$name")"
  cron="$(timer_cron_path "$name")"
  if [[ -f "$timer" ]]; then
    printf '%s: systemd timer %s\n' "$name" "$(systemctl is-active "$(timer_unit_name "$name").timer" 2>/dev/null || printf 'inactive')"
    return 0
  fi
  if [[ -f "$cron" ]]; then
    printf '%s: cron file %s\n' "$name" "$cron"
    return 0
  fi
  printf '%s: not scheduled\n' "$name"
  return 1
}
