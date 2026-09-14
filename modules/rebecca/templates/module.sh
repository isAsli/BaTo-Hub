#!/usr/bin/env bash
. /opt/batohub/lib/common.sh
TEMPLATE_SRC=/opt/batohub/templates/rebecca/subscription/index.html
TEMPLATE_DST="$TEMPLATE_ROOT/subscription/index.html"
templates_menu(){ while :; do clear; banner 'Rebecca / Templates'; printf '%s\n' '1) نصب BaTo-Ui' '2) وضعیت' '3) حذف BaTo-Ui' '0) بازگشت'; read -r -p 'انتخاب: ' c; case "$c" in 1) template_install;; 2) template_status;; 3) template_remove;; 0) return;; esac; done; }
template_install(){
 clear; banner 'Rebecca / Templates / BaTo-Ui'; [ -f "$REBECCA_DIR/.env" ] || { err 'Rebecca .env not found.'; pause; return; }; install -d -m 750 "$TEMPLATE_ROOT/subscription"; install -m 640 "$TEMPLATE_SRC" "$TEMPLATE_DST" || { err 'Template copy failed.'; pause; return; }
 if grep -qE '^CUSTOM_TEMPLATES_DIRECTORY=' "$REBECCA_DIR/.env"; then sed -i "s|^CUSTOM_TEMPLATES_DIRECTORY=.*|CUSTOM_TEMPLATES_DIRECTORY=$TEMPLATE_ROOT|" "$REBECCA_DIR/.env"; else printf '\nCUSTOM_TEMPLATES_DIRECTORY=%s\n' "$TEMPLATE_ROOT" >> "$REBECCA_DIR/.env"; fi
 if grep -qE '^SUBSCRIPTION_PAGE_TEMPLATE=' "$REBECCA_DIR/.env"; then sed -i 's|^SUBSCRIPTION_PAGE_TEMPLATE=.*|SUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html|' "$REBECCA_DIR/.env"; else printf '\nSUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html\n' >> "$REBECCA_DIR/.env"; fi
 chmod 750 "$TEMPLATE_ROOT" "$TEMPLATE_ROOT/subscription"; chmod 640 "$TEMPLATE_DST"; chown -R root:root "$TEMPLATE_ROOT"
 systemctl restart rebecca 2>>"$LOG_FILE" || true
 ok 'BaTo-Ui installed'; printf '\n%s\n%s\n' "CUSTOM_TEMPLATES_DIRECTORY=$TEMPLATE_ROOT" 'SUBSCRIPTION_PAGE_TEMPLATE=subscription/index.html'; pause
}
template_status(){ clear; banner 'Rebecca / Templates / Status'; [ -f "$TEMPLATE_DST" ] && ok "Installed: $TEMPLATE_DST" || err 'BaTo-Ui is not installed.'; grep -E '^(CUSTOM_TEMPLATES_DIRECTORY|SUBSCRIPTION_PAGE_TEMPLATE)=' "$REBECCA_DIR/.env" 2>/dev/null || true; pause; }
template_remove(){ clear; banner 'Rebecca / Templates / Remove'; read -r -p 'برای حذف عبارت REMOVE را وارد کنید: ' x; [ "$x" = REMOVE ] || return; rm -f "$TEMPLATE_DST"; rmdir "$TEMPLATE_ROOT/subscription" 2>/dev/null || true; ok 'BaTo-Ui removed'; pause; }
