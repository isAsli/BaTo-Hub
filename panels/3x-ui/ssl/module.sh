#!/usr/bin/env bash
set -euo pipefail

. /opt/batohub/lib/common.sh

ssl_menu() {
  clear
  banner '3X-UI / SSL'
  printf '%s\n' 'Not implemented in this release.'
  pause
}

ssl_install() {
  err "SSL installation is not implemented for 3X-UI in this release."
  return 1
}

ssl_renew() {
  err "SSL renewal is not implemented for 3X-UI in this release."
  return 1
}

ssl_status() {
  err "SSL status is not implemented for 3X-UI in this release."
  return 1
}

ssl_remove() {
  err "SSL removal is not implemented for 3X-UI in this release."
  return 1
}
