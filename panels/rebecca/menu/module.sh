#!/usr/bin/env bash
set -euo pipefail

panel_menu() {
  while :; do
    clear
    banner 'Rebecca'
    printf '%s\n' '----------------------------------------'
    printf '%s\n' '1) SSL'
    printf '%s\n' '2) Subscription template'
    printf '%s\n' '3) Update and status'
    printf '%s\n' '4) Panel logs'
    printf '%s\n' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1) ssl_menu;;
      2) template_menu;;
      3)
        clear
        banner 'Rebecca / Update and status'
        panel_status
        pause
        ;;
      4) panel_logs;;
      0) return;;
    esac
  done
}
