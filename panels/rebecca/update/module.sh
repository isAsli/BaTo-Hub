#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

panel_update() {
  clear
  banner 'Rebecca / Update'
  info 'Rebecca update is delegated to the upstream Rebecca installer.'
  local url="https://raw.githubusercontent.com/rebeccapanel/Rebecca/master/scripts/rebecca/rebecca-binary.sh"
  local tmp
  tmp=$(mktemp_file "rebecca_update")
  if curl -fsSL --max-time 20 --cacert /etc/ssl/certs/ca-certificates.crt "$url" -o "$tmp" 2>>"$LOG_FILE"; then
    if bash "$tmp" update 2>&1 | tee -a "$LOG_FILE"; then
      ok 'Rebecca update completed'
    else
      err 'Rebecca update failed'
      show_last_logs
    fi
    rm -f "$tmp"
  else
    err 'Rebecca updater unavailable'
    rm -f "$tmp"
  fi
  pause
}
