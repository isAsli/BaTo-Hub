#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_SRC="${INSTALL_DIR:-/opt/batohub}/templates/rebecca/subscription/index.html"
TEMPLATE_DST="$TEMPLATE_ROOT/subscription/index.html"

templates_menu() {
  while :; do
    clear
    banner 'Rebecca / Templates'
    printf '%s\n' '1) Install BaTo-Ui' '2) Status' '3) Remove BaTo-Ui' '0) Back'
    read -r -p 'Selection: ' c
    case "$c" in
      1) template_install;;
      2) template_status;;
      3) template_remove;;
      0) return;;
    esac
  done
}

template_install() {
  clear
  banner 'Rebecca / Templates / BaTo-Ui'
  if [ ! -f "$REBECCA_DIR/.env" ]; then
    err 'Rebecca .env not found.'
    pause
    return
  fi

  install -d -m 750 "$TEMPLATE_ROOT/subscription"
  install -m 640 "$TEMPLATE_SRC" "$TEMPLATE_DST" || {
    err 'Template copy failed.'
    pause
    return
  }

  local fd
  fd=$(lock_acquire "$REBECCA_DIR/.env.lock")
  if grep -qE '^CUSTOM_TEMPLATES_DIRECTORY=' "$REBECCA_DIR/.env"; then
    sed -i "s|^CUSTOM_TEMPLATES_DIRECTORY=.*|CUSTOM_TEMPLATES_DIRECTORY=$TEMPLATE_ROOT|" "$REBECCA_DIR/.env"
  else
    printf '\nCUSTOM_TEMPLATES_DIRECTORY=%s\n' "$TEMPLATE_ROOT" >> "$REBECCA_DIR/.env"
  fi
  if grep -qE '^SUBSCRIPTION_PAGE_TEMPLATE=' "$REBECCA_DIR/.env"; then
    sed -i 's|^SUBSCRIPTION_PAGE_TEMPLATE=.*|SUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html|' "$REBECCA_DIR/.env"
  else
    printf '\nSUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html\n' >> "$REBECCA_DIR/.env"
  fi
  chmod 750 "$TEMPLATE_ROOT" "$TEMPLATE_ROOT/subscription"
  chmod 640 "$TEMPLATE_DST"
  chown -R root:root "$TEMPLATE_ROOT"
  lock_release "$fd"

  systemctl restart rebecca 2>>"$LOG_FILE" || true

  ok 'BaTo-Ui installed'
  printf '\n%s\n%s\n' "CUSTOM_TEMPLATES_DIRECTORY=$TEMPLATE_ROOT" 'SUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html'
  pause
}

template_status() {
  clear
  banner 'Rebecca / Templates / Status'
  if [ -f "$TEMPLATE_DST" ]; then
    ok "Installed: $TEMPLATE_DST"
  else
    err 'BaTo-Ui is not installed.'
  fi
  grep -E '^(CUSTOM_TEMPLATES_DIRECTORY|SUBSCRIPTION_PAGE_TEMPLATE)=' "$REBECCA_DIR/.env" 2>/dev/null || true
  pause
}

template_remove() {
  clear
  banner 'Rebecca / Templates / Remove'
  local x
  read -r -p 'To remove, type REMOVE: ' x
  if [ "${x:-}" != "REMOVE" ]; then
    return
  fi
  rm -f "$TEMPLATE_DST"
  rmdir "$TEMPLATE_ROOT/subscription" 2>/dev/null || true
  ok 'BaTo-Ui removed'
  pause
}
