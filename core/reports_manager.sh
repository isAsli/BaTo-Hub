#!/usr/bin/env bash
set -Eeuo pipefail

# The Reports section.

reports_choose_name() {
  local names=() name choice index=0
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(report_names)
  ui_title "Choose a report"
  for name in "${names[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$name"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" == 0 ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  name="${names[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 1
  }
  printf '%s\n' "$name"
}

reports_view_flow() {
  local name format choice
  name="$(reports_choose_name)" || return 0
  ui_title "Format"
  printf '1) Screen table\n'
  printf '2) CSV\n'
  printf '3) JSON\n'
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  case "$choice" in
  1) format="screen" ;;
  2) format="csv" ;;
  3) format="json" ;;
  *) return 0 ;;
  esac
  ui_title "Report: ${name}"
  report_render "$name" "$format"
  pause
}

reports_export_flow() {
  local name format target
  need_root || return 1
  name="$(reports_choose_name)" || return 0
  ui_title "Export format"
  printf '1) CSV\n'
  printf '2) JSON\n'
  printf '0) Back\n'
  case "$(ui_menu_choice)" in
  1) format="csv" ;;
  2) format="json" ;;
  *) return 0 ;;
  esac
  target="$(report_export "$name" "$format")" || return 1
  ok "Export written: ${target}"
  return 0
}

reports_exports_lines() {
  local file
  if [[ ! -d "$REPORTS_DIR" ]]; then
    printf '  No export directory exists yet.\n'
    return 0
  fi
  local found=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    found=1
    printf '  %-44s %s bytes  %s\n' "$(basename "$file")" "$(stat -c '%s' "$file" 2>/dev/null || printf '0')" \
      "$(date -r "$file" '+%F %T' 2>/dev/null || printf unknown)"
  done < <(find "$REPORTS_DIR" -maxdepth 1 -type f | sort)
  [[ "$found" -eq 1 ]] || printf '  No export has been written yet.\n'
  return 0
}

reports_menu() {
  local choice
  while true; do
    ui_title "Reports"
    printf 'Export directory: %s\n' "$REPORTS_DIR"
    printf 'Exports kept: %s\n\n' "$REPORT_KEEP"
    printf '1) View a report on screen\n'
    printf '2) Export a report\n'
    printf '3) List the exports\n'
    printf '4) Remove the oldest exports\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) reports_view_flow ;;
    2)
      reports_export_flow || true
      pause
      ;;
    3)
      reports_exports_lines
      pause
      ;;
    4)
      need_root || return 1
      report_rotate "$REPORT_KEEP"
      ok "Only the newest ${REPORT_KEEP} exports were kept."
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

reports_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  list) report_names ;;
  show)
    report_render "${1:?report name is required}" "${2:-screen}"
    ;;
  export)
    need_root || return 1
    report_export "${1:?report name is required}" "${2:-csv}"
    ;;
  exports) reports_exports_lines ;;
  rotate)
    need_root || return 1
    report_rotate "${1:-$REPORT_KEEP}"
    ;;
  *)
    err "Unknown reports command: ${command:-<none>}"
    printf 'Report commands: list, show <report> [screen|csv|json], export <report> [csv|json], exports, rotate\n'
    return 2
    ;;
  esac
}
