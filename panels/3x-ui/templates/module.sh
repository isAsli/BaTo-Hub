#!/usr/bin/env bash
set -Eeuo pipefail

# 3X-UI template handling.
#
# 3X-UI generates subscription output from settings stored in its own database
# and offers no documented external template directory. BaToHub therefore stages
# the template inside its own state storage and reports exactly that, instead of
# editing the panel database.

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
