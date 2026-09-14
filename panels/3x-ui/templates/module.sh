#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

template_menu() {
  clear
  banner '3X-UI / Templates'
  printf '%s\n' 'Not implemented in this release.'
  pause
}

template_apply() {
  err "Template application is not implemented for 3X-UI in this release."
  return 1
}

template_remove() {
  err "Template removal is not implemented for 3X-UI in this release."
  return 1
}
