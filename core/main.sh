#!/usr/bin/env bash
. /opt/batohub/lib/common.sh
. /opt/batohub/core/license.sh
. /opt/batohub/modules/rebecca/ssl/module.sh
. /opt/batohub/modules/rebecca/templates/module.sh
. /opt/batohub/modules/rebecca/rebecca_core.sh

banner(){
  clear
  printf '\033[36m╔══════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[36m║\033[0m                 \033[97mBaToHub\033[0m \033[90mv%s\033[0m                  \033[36m║\033[0m\n' "$APP_VERSION"
  printf '\033[36m║\033[0m              \033[90mCentral Server Manager\033[0m             \033[36m║\033[0m\n'
  printf '\033[36m╚══════════════════════════════════════════════════════════╝\033[0m\n'
}

pause(){ read -r -p $'\nEnter برای ادامه...' _; }

server_menu(){
  while :; do
    clear
    banner
    printf '%s\n' '1) اطلاعات و وضعیت سرور' '2) سرویس‌ها' '3) منابع سیستم' '4) شبکه' '5) لاگ‌های BaToHub' '0) بازگشت'
    read -r -p 'انتخاب: ' c
    case "$c" in
      1)
        clear; banner
        printf 'Hostname: '; hostname
        printf 'OS: '; . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}"
        printf 'Kernel: '; uname -r
        printf 'Arch: '; uname -m
        pause
        ;;
      2)
        clear; banner
        systemctl --no-pager --type=service --state=running | head -35
        pause
        ;;
      3)
        clear; banner
        free -h
        echo
        df -h / /opt 2>/dev/null
        pause
        ;;
      4)
        clear; banner
        ip -brief address 2>/dev/null || true
        echo
        ss -lntup 2>/dev/null | head -40
        pause
        ;;
      5)
        clear; banner
        tail -n 80 "$LOG_FILE" 2>/dev/null
        pause
        ;;
      0) return;;
    esac
  done
}

update_all(){ . /opt/batohub/core/update.sh; update_all; }

update_module(){
  clear; banner
  local module="$1" url=""
  case "$module" in
    rebecca) url="https://raw.githubusercontent.com/rebeccapanel/Rebecca/master/scripts/rebecca/rebecca-binary.sh";;
  esac
  [ -n "$url" ] || { err 'No updater registered for this module.'; pause; return; }
  curl -fsSL "$url" -o /tmp/rebecca-updater.sh && bash /tmp/rebecca-updater.sh update && ok 'Rebecca update completed' || err 'Rebecca update failed'
  rm -f /tmp/rebecca-updater.sh
  pause
}

tools_menu(){
  while :; do
    clear
    banner
    printf '%s\n' '1) Rebecca' '2) PasarGuard' '3) Sanaei / 3X-UI' '0) بازگشت'
    read -r -p 'انتخاب: ' c
    case "$c" in
      1) rebecca_menu;;
      2)
        clear; banner
        printf '\\033[33mPasarGuard در نسخه 0.0.1 فعال نشده است.\\033[0m\\n'
        pause
        ;;
      3)
        clear; banner
        printf '\\033[33mSanaei / 3X-UI در نسخه 0.0.1 فعال نشده است.\\033[0m\\n'
        pause
        ;;
      0) return;;
    esac
  done
}

rebecca_menu(){
  while :; do
    clear
    banner
    printf '%s\n' \
      'Rebecca' \
      '──────────────' \
      '1) SSL' \
      '2) Template / BaTo-Ui' \
      '3) Update Rebecca' \
      '4) Status' \
      '5) Remove BaToHub changes' \
      '6) Template / BaTo-Ui' \
      '7) Remove BaTo-Ui' \
      '8) Rebecca Logs' \
      '0) Back'
    read -r -p 'انتخاب: ' c
    case "$c" in
      1) ssl_menu;;
      2) templates_menu;;
      3) update_module rebecca;;
      4)
        clear; banner
        systemctl --no-pager status rebecca 2>&1 | head -n 45
        if [ -f /opt/rebecca/.env ]; then
          grep -E '^(UVICORN_SSL_CERTFILE|UVICORN_SSL_KEYFILE|REBECCA_CERT_BASE|CUSTOM_TEMPLATES_DIRECTORY|SUBSCRIPTION_PAGE_TEMPLATE)=' /opt/rebecca/.env || true
        fi
        pause
        ;;
      5)
        clear; banner
        read -r -p 'برای حذف تغییرات BaToHub عبارت REMOVE را وارد کنید: ' x
        if [ "$x" = REMOVE ]; then
          rm -rf "$TEMPLATE_ROOT"
          sed -i '/^CUSTOM_TEMPLATES_DIRECTORY=/d;/^SUBSCRIPTION_PAGE_TEMPLATE=/d' /opt/rebecca/.env 2>/dev/null || true
          ok 'BaToHub template changes removed'
        fi
        pause
        ;;
      6) templates_menu;;
      7) template_remove;;
      8)
        clear; banner
        printf '%s\n' 'BaToHub Logs — Rebecca entries'
        grep -iE 'rebecca|ssl|template|certbot|letsencrypt' "$LOG_FILE" 2>/dev/null | tail -n 120 || printf '%s\n' 'No Rebecca-related log entries found.'
        pause
        ;;
      0) return;;
    esac
  done
}

license_menu(){
  clear; banner
  printf '%s\n' '1) اعتبارسنجی مجدد' '2) وضعیت License' '0) بازگشت'
  read -r -p 'انتخاب: ' c
  case "$c" in
    1)
      rm -f /etc/batohub/.license_key
      ensure_license
      pause
      ;;
    2)
      if [ -f /etc/batohub/license.json ]; then
        cat /etc/batohub/license.json
      else
        err 'No local license receipt.'
      fi
      pause
      ;;
    0) return;;
  esac
}

main_menu(){
  ensure_license || exit 1
  while :; do
    clear
    banner
    printf '%s\n' '1) Update' '2) Session & Server' '3) Tools' '4) License' '5) Settings' '6) Logs' '7) Repair' '8) Uninstall' '0) Exit'
    read -r -p 'انتخاب: ' c
    case "$c" in
      1) update_all;;
      2) server_menu;;
      3) tools_menu;;
      4) license_menu;;
      5)
        clear; banner
        cat /etc/batohub/batohub.conf
        pause
        ;;
      6)
        clear; banner
        tail -n 120 "$LOG_FILE" 2>/dev/null
        pause
        ;;
      7)
        clear; banner
        install -d -m 750 /etc/batohub /var/lib/batohub /var/log/batohub
        chmod 700 /etc/batohub
        ok 'BaToHub directories repaired'
        pause
        ;;
      8)
        clear; banner
        read -r -p 'برای حذف BaToHub عبارت UNINSTALL را وارد کنید: ' x
        if [ "$x" = UNINSTALL ]; then
          /opt/batohub/bin/uninstall
        fi
        return
        ;;
      0) return;;
    esac
  done
}

main_menu
