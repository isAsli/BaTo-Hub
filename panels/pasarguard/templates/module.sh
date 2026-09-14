#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

template_menu() {
  clear
  banner 'PasarGuard / Templates'
  printf '%s\n' 'Not implemented in this release.'
  pause
}

template_apply() {
  err "Template application is not implemented for PasarGuard in this release."
  return 1
}

template_remove() {
  err "Template removal is not implemented for PasarGuard in this release."
  return 1
}
