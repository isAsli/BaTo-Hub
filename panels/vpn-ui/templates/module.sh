#!/usr/bin/env bash
set -Eeuo pipefail

# VPN-UI template handling.
#
# The panel serves subscription output from its own settings and database, so
# BaToHub stages a template in its own state storage and says so plainly.

template_apply() {
  need_root || return 1
  template_stage_apply
}

template_status() {
  template_stage_status
}

template_remove() {
  need_root || return 1
  template_stage_remove
}
