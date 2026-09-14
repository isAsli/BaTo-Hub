#!/usr/bin/env bash
set -euo pipefail

3xui_menu() {
  clear
  banner 'Sanaei / 3X-UI'
  printf '%s\n' 'Not implemented in this release.'
  printf '%s\n' 'This module is reserved for a future version of BaToHub.'
  pause
}

3xui_install() {
  err 'Sanaei / 3X-UI integration is not implemented.'
  return 1
}

3xui_uninstall() {
  err 'Nothing to uninstall.'
  return 0
}

3xui_status() {
  err 'Sanaei / 3X-UI integration is not implemented.'
  return 1
}

3xui_update() {
  err 'Sanaei / 3X-UI integration is not implemented.'
  return 1
}
