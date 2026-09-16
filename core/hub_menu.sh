#!/usr/bin/env bash
set -Eeuo pipefail

# The main menu of BaToHub.
#
# The menu is built from the permissions of the current account, so a role is
# visible in the interface and not only enforced when an action is attempted. An
# entry whose permission is missing is not shown at all, and the same permission
# is checked again by the section it opens.

hub_entry_allowed() {
  local permission="$1"
  [[ -z "$permission" ]] && return 0
  admin_has_permission "$permission"
}

hub_header() {
  local panel
  panel="$(panel_config_name)"
  ui_title "Main menu"
  printf 'Account: %s (%s)\n' "$(admin_current_user)" "$(admin_current_role)"
  printf 'Managed panel: %s\n' "$(panel_display_for "$panel" 2>/dev/null || printf 'not configured')"
  printf 'BaToHub: %s\n\n' "$APP_VERSION"
}

hub_menu() {
  local choice
  while true; do
    hub_header
    printf '1) Panels\n'
    hub_entry_allowed servers.view && printf '2) Servers and nodes\n'
    hub_entry_allowed ssl.issue && printf '3) SSL\n'
    hub_entry_allowed backup.create && printf '4) Backup and restore\n'
    hub_entry_allowed backup.create && printf '5) Backup delivery to Telegram\n'
    hub_entry_allowed migration.run && printf '6) Migration\n'
    hub_entry_allowed tools.run && printf '7) Server Tools\n'
    hub_entry_allowed panels.view && printf '8) Docker\n'
    hub_entry_allowed alerts.view && printf '9) Alerts\n'
    hub_entry_allowed panels.view && printf '10) Reports\n'
    hub_entry_allowed settings.edit && printf '11) Telegram bot\n'
    hub_entry_allowed admins.manage && printf '12) Admins\n'
    hub_entry_allowed tools.run && printf '13) Tools\n'
    hub_entry_allowed settings.edit && printf '14) Settings\n'
    hub_entry_allowed settings.edit && printf '15) Integrity\n'
    hub_entry_allowed update.run && printf '16) Update BaToHub\n'
    printf '0) Exit\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) hub_panels_flow ;;
    2)
      hub_entry_allowed servers.view || {
        warn 'Not permitted.'
        continue
      }
      nodes_menu
      ;;
    3)
      hub_entry_allowed ssl.issue || {
        warn 'Not permitted.'
        continue
      }
      ssl_menu_multi
      ;;
    4)
      hub_entry_allowed backup.create || {
        warn 'Not permitted.'
        continue
      }
      backup_menu
      ;;
    5)
      hub_entry_allowed backup.create || {
        warn 'Not permitted.'
        continue
      }
      backup_delivery_menu
      ;;
    6)
      hub_entry_allowed migration.run || {
        warn 'Not permitted.'
        continue
      }
      migration_menu
      ;;
    7)
      hub_entry_allowed tools.run || {
        warn 'Not permitted.'
        continue
      }
      server_tools_menu
      ;;
    8)
      hub_entry_allowed panels.view || {
        warn 'Not permitted.'
        continue
      }
      container_menu
      ;;
    9)
      hub_entry_allowed alerts.view || {
        warn 'Not permitted.'
        continue
      }
      alerts_menu
      ;;
    10)
      hub_entry_allowed panels.view || {
        warn 'Not permitted.'
        continue
      }
      reports_menu
      ;;
    11)
      hub_entry_allowed settings.edit || {
        warn 'Not permitted.'
        continue
      }
      bot_menu
      ;;
    12)
      hub_entry_allowed admins.manage || {
        warn 'Not permitted.'
        continue
      }
      admins_menu
      ;;
    13)
      hub_entry_allowed tools.run || {
        warn 'Not permitted.'
        continue
      }
      tools_menu
      ;;
    14)
      hub_entry_allowed settings.edit || {
        warn 'Not permitted.'
        continue
      }
      settings_menu
      ;;
    15)
      hub_entry_allowed settings.edit || {
        warn 'Not permitted.'
        continue
      }
      integrity_menu
      ;;
    16)
      hub_entry_allowed update.run || {
        warn 'Not permitted.'
        continue
      }
      update_menu
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

# The panel entry: choosing the managed panel and then its own operations.
hub_panels_flow() {
  local choice panel
  while true; do
    panel="$(panel_config_name)"
    ui_title "Panels"
    printf 'Managed panel: %s\n\n' "${panel:-not configured}"
    printf '1) Panel operations\n'
    hub_entry_allowed panels.install && printf '2) Install a panel\n'
    hub_entry_allowed panels.update && printf '3) Change the managed panel\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      if [[ -z "$panel" ]]; then
        warn "No panel is configured. Choose one first."
        pause
        continue
      fi
      if ! panel_exists "$panel"; then
        err "The configured panel is not available in this release: $panel"
        pause
        continue
      fi
      selected_panel_menu "$panel"
      ;;
    2)
      hub_entry_allowed panels.install || {
        warn 'Not permitted.'
        continue
      }
      panel_install_menu
      ;;
    3)
      hub_entry_allowed panels.update || {
        warn 'Not permitted.'
        continue
      }
      printf 'Switching the managed panel does not modify or remove the previous panel.\n'
      if ui_confirm 'Continue?'; then
        panel_choice_menu
      fi
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}
