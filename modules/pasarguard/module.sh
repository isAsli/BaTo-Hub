#!/usr/bin/env bash
set -euo pipefail

pasarguard_menu() {
  clear
  banner 'PasarGuard'
  printf '%s\n' 'Not implemented in this release.'
  printf '%s\n' 'This module is reserved for a future version of BaToHub.'
  pause
}

pasarguard_install() {
  err 'PasarGuard integration is not implemented.'
  return 1
}

pasarguard_uninstall() {
  err 'Nothing to uninstall.'
  return 0
}

pasarguard_status() {
  err 'PasarGuard integration is not implemented.'
  return 1
}

pasarguard_update() {
  err 'PasarGuard integration is not implemented.'
  return 1
}
