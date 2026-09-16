#!/usr/bin/env bash
set -Eeuo pipefail

# Reports.
#
# Every report is a function that prints a tab separated header line followed by
# one tab separated line per row. A single renderer turns that into a screen
# table, a CSV file or a JSON array, so a new report is one function and no
# format handling. Exports are written to ${STATE_DIR}/reports and old exports are
# rotated.
#
# A report reads the state BaToHub keeps: the panel APIs, the BaToHub logs, the
# certificate registrations, the backup directory and the administrator log. It
# never invents a figure: when a source is unavailable the report says so.

REPORTS_DIR="${STATE_DIR}/reports"
REPORT_KEEP="${REPORT_KEEP:-20}"

report_names() {
  printf '%s\n' \
    panel_traffic \
    user_traffic \
    user_counts \
    active_users \
    expired_users \
    ssl_status \
    backup_history \
    update_history \
    alert_history \
    admin_actions
  return 0
}

report_valid() {
  local name
  while IFS= read -r name; do
    [[ "$name" == "${1:-}" ]] && return 0
  done < <(report_names)
  return 1
}

report_header_panel_traffic() { printf 'panel\tusers\ttraffic_bytes\n'; }
report_header_user_traffic() { printf 'panel\tuser\ttraffic_bytes\n'; }
report_header_user_counts() { printf 'panel\tusers\n'; }
report_header_active_users() { printf 'panel\tuser\tstatus\texpire\n'; }
report_header_expired_users() { printf 'panel\tuser\tstatus\texpire\n'; }
report_header_ssl_status() { printf 'panel\tdomain\tpurpose\tmethod\tissued\texpires_in_days\n'; }
report_header_backup_history() { printf 'archive\tbytes\tcreated\n'; }
report_header_update_history() { printf 'time\toutcome\n'; }
report_header_alert_history() { printf 'time\talert\tdetail\n'; }
report_header_admin_actions() { printf 'time\taccount\taction\n'; }

# Reads the user list of one panel. Prints one tab separated line per user in the
# order the panel declares; a panel that cannot be read prints nothing and is
# reported by the caller.
report_panel_users() {
  local panel="$1" url
  local -a fields=()
  [[ "$(migration_mode "$panel")" == "users" ]] || return 1
  url="$(nodes_api_base "$panel")$(panel_meta_get "$panel" users.list_path)"
  while IFS= read -r field; do
    [[ -n "$field" ]] && fields+=("$field")
  done < <(panel_meta_list "$panel" users.list_fields 2>/dev/null || true)
  [[ "${#fields[@]}" -gt 0 ]] || fields=(username status expire data_limit used_traffic)
  nodes_api_call "$panel" GET "$url" >/dev/null 2>&1 || return 1
  api_status_ok || return 1
  printf '%s' "$API_BODY" | api_json_rows "$(panel_meta_get "$panel" users.list_container 2>/dev/null || printf '')" "${fields[@]}"
}

report_rows_panel_traffic() {
  local panel line total count
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    [[ "$(migration_mode "$panel")" == "users" ]] || continue
    total=0
    count=0
    while IFS=$'\t' read -r line; do
      [[ -n "$line" ]] || continue
      count=$((count + 1))
      total=$((total + $(printf '%s' "$line" | awk -F'\t' '{ value = $5; gsub(/[^0-9]/, "", value); print value + 0 }')))
    done < <(report_panel_users "$panel" 2>/dev/null || true)
    printf '%s\t%s\t%s\n' "$panel" "$count" "$total"
  done < <(loader_panels)
  return 0
}

report_rows_user_traffic() {
  local panel username used line
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    [[ "$(migration_mode "$panel")" == "users" ]] || continue
    while IFS=$'\t' read -r line; do
      [[ -n "$line" ]] || continue
      username="$(printf '%s' "$line" | cut -f1)"
      used="$(printf '%s' "$line" | awk -F'\t' '{ value = $5; gsub(/[^0-9]/, "", value); print value + 0 }')"
      printf '%s\t%s\t%s\n' "$panel" "${username:-<unnamed>}" "$used"
    done < <(report_panel_users "$panel" 2>/dev/null || true)
  done < <(loader_panels)
  return 0
}

report_rows_user_counts() {
  local panel count
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    [[ "$(migration_mode "$panel")" == "users" ]] || continue
    count="$(report_panel_users "$panel" 2>/dev/null | grep -c . || true)"
    printf '%s\t%s\n' "$panel" "${count:-0}"
  done < <(loader_panels)
  return 0
}

# A user is active when the panel reports it as active and its expiry has not
# passed; expired when the panel reports it as expired or the expiry is in the
# past. The panel's own wording is kept in the status column.
report_rows_active_users() {
  local panel line username status expire now
  now="$(date +%s)"
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    while IFS=$'\t' read -r line; do
      [[ -n "$line" ]] || continue
      username="$(printf '%s' "$line" | cut -f1)"
      status="$(printf '%s' "$line" | cut -f2)"
      expire="$(printf '%s' "$line" | cut -f3)"
      [[ "$status" == "active" ]] || continue
      if [[ "$expire" =~ ^[0-9]+$ && "$expire" -gt 0 && "$expire" -lt "$now" ]]; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$panel" "${username:-<unnamed>}" "$status" "${expire:-0}"
    done < <(report_panel_users "$panel" 2>/dev/null || true)
  done < <(loader_panels)
  return 0
}

report_rows_expired_users() {
  local panel line username status expire now
  now="$(date +%s)"
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    while IFS=$'\t' read -r line; do
      [[ -n "$line" ]] || continue
      username="$(printf '%s' "$line" | cut -f1)"
      status="$(printf '%s' "$line" | cut -f2)"
      expire="$(printf '%s' "$line" | cut -f3)"
      if [[ "$status" != "expired" ]]; then
        if [[ ! "$expire" =~ ^[0-9]+$ || "$expire" -eq 0 || "$expire" -ge "$now" ]]; then
          continue
        fi
      fi
      printf '%s\t%s\t%s\t%s\n' "$panel" "${username:-<unnamed>}" "${status:-expired}" "${expire:-0}"
    done < <(report_panel_users "$panel" 2>/dev/null || true)
  done < <(loader_panels)
  return 0
}

report_rows_ssl_status() {
  local panel name purpose method issued cert days
  while IFS= read -r panel; do
    [[ -n "$panel" ]] || continue
    while IFS=' ' read -r name purpose method issued _; do
      [[ -n "$name" ]] || continue
      cert="${STATE_DIR}/panels/${panel}/ssl/$(ssl_target_slug "$name")/fullchain.pem"
      days="unknown"
      [[ -s "$cert" ]] && days="$(ssl_days_remaining "$cert" 2>/dev/null || printf 'unknown')"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$panel" "$name" "$purpose" "$method" "${issued:--}" "$days"
    done < <(ssl_domains_list "$panel")
  done < <(loader_panels)
  return 0
}

report_rows_backup_history() {
  local file
  [[ -d "$BACKUP_DIR" ]] || return 0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    printf '%s\t%s\t%s\n' "$(basename "$file")" "$(stat -c '%s' "$file" 2>/dev/null || printf '0')" \
      "$(date -r "$file" '+%F %T' 2>/dev/null || printf unknown)"
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' | sort)
  return 0
}

report_rows_update_history() {
  local log="${LOG_DIR}/update.log"
  [[ -r "$log" ]] || return 0
  grep -E 'update completed|update aborted|rolling back|post-update verification failed|no update needed|downgrade refused|update started|rollback completed|pre-update backup' "$log" |
    sed -E 's/^\[([^]]*)\][[:space:]]*\[update\][[:space:]]*/\1\t/' || true
  return 0
}

report_rows_alert_history() {
  [[ -r "$ALERT_LOG" ]] || return 0
  sed -E 's/^\[([^]]*)\][[:space:]]*/\1\t/' "$ALERT_LOG" |
    awk -F'\t' '{ detail = $2; sub(/^delivered alert=[^ ]+ +/, "", detail); alert = $2; sub(/^[a-z]+ alert=/, "", alert); sub(/ .*/, "", alert); printf "%s\t%s\t%s\n", $1, alert, detail }'
  return 0
}

report_rows_admin_actions() {
  [[ -r "$ADMIN_LOG" ]] || return 0
  sed -E 's/^\[([^]]*)\][[:space:]]*user=([^ ]+)[[:space:]]*/\1\t\2\t/' "$ADMIN_LOG"
  return 0
}

# report_rows NAME prints the header and the rows of one report as one stream.
report_rows() {
  local name="$1"
  report_valid "$name" || {
    err "Unknown report: ${name}"
    return 2
  }
  "report_header_${name}"
  "report_rows_${name}" 2>/dev/null || true
  return 0
}

# One renderer for the three formats. The screen form is a padded table, CSV is
# quoted per field, and JSON is an array of objects keyed by the header.
report_format_rows() {
  local format="$1"
  python3 -c '
import csv
import json
import sys

fmt = sys.argv[1]
rows = [line.rstrip("\n").split("\t") for line in sys.stdin if line.strip()]
if not rows:
    if fmt == "json":
        print("[]")
    raise SystemExit(0)

header, data = rows[0], rows[1:]

if fmt == "json":
    print(json.dumps([dict(zip(header, row)) for row in data], indent=2))
elif fmt == "csv":
    writer = csv.writer(sys.stdout)
    writer.writerow(header)
    writer.writerows(data)
else:
    widths = [len(name) for name in header]
    for row in data:
        for index, value in enumerate(row[: len(widths)]):
            widths[index] = max(widths[index], len(value))
    def render(cells):
        return "  ".join(
            (cells[index] if index < len(cells) else "").ljust(widths[index])
            for index in range(len(widths))
        ).rstrip()
    print(render(header))
    print("  ".join("-" * width for width in widths))
    for row in data:
        print(render(row))
    print("")
    print(f"{len(data)} row(s)")
' "$format"
}

report_render() {
  local name="$1" format="${2:-screen}"
  case "$format" in
  screen | csv | json) ;;
  *)
    err "Unknown format: ${format}. Use screen, csv or json."
    return 2
    ;;
  esac
  report_rows "$name" | report_format_rows "$format"
  return 0
}

report_dir_ensure() {
  install -d -m 0750 -o root -g root "$REPORTS_DIR"
  harden_dir "$REPORTS_DIR" 0750
  return 0
}

# Keeps the newest exports and removes the oldest, so an export directory does
# not grow without limit.
report_rotate() {
  local keep="$1" file count=0
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=20
  local -a files=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(find "$REPORTS_DIR" -maxdepth 1 -type f | sort)
  count="${#files[@]}"
  [[ "$count" -le "$keep" ]] && return 0
  local index
  for ((index = 0; index < count - keep; index++)); do
    rm -f -- "${files[index]}"
  done
  return 0
}

report_export() {
  local name="$1" format="${2:-csv}" stamp target
  report_valid "$name" || {
    err "Unknown report: ${name}"
    return 2
  }
  case "$format" in
  csv | json) ;;
  *)
    err "An export is written as csv or json."
    return 2
    ;;
  esac
  report_dir_ensure || return 1
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  target="${REPORTS_DIR}/${name}-${stamp}.${format}"
  if ! report_render "$name" "$format" >"$target"; then
    rm -f -- "$target"
    err "The report could not be rendered."
    return 1
  fi
  # An export names panels, users and addresses, so it is readable by root only.
  chmod 0600 "$target"
  chown root:root "$target" 2>/dev/null || true
  report_rotate "$REPORT_KEEP"
  printf '%s\n' "$target"
  return 0
}
