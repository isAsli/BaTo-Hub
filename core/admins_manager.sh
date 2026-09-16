#!/usr/bin/env bash
set -Eeuo pipefail

# The Admins section.
#
# The interactive menu shows only the entries the current account is allowed to
# use, so a role is not merely enforced when an action is attempted.

admins_status() {
  printf 'Configuration file: %s\n' "$ADMIN_CONF"
  printf 'Action log: %s\n' "$ADMIN_LOG"
  printf 'Current account: %s\n' "$(admin_current_user)"
  printf 'Current role: %s\n\n' "$(admin_current_role)"
  admin_list_lines
  return 0
}

admins_add_flow() {
  local username role permissions choice index=0
  need_root || return 1
  admin_require admins.manage || return 1
  ui_title "Add an administrator"
  printf 'The password is stored as a SHA-512 crypt hash and is never printed.\n\n'
  username="$(trim "$(ui_prompt 'Account name: ' '')")"
  [[ -n "$username" ]] || {
    warn "An account name is required."
    return 1
  }
  ui_title "Role"
  while IFS= read -r role; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$role"
  done < <(admin_roles)
  choice="$(ui_menu_choice)"
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  role="$(admin_roles | sed -n "${choice}p")"
  [[ -n "$role" ]] || {
    warn "Invalid selection."
    return 1
  }
  permissions=""
  admin_add "$username" "$role" "$permissions"
}

admins_remove_flow() {
  local username
  need_root || return 1
  admin_require admins.manage || return 1
  ui_title "Remove an administrator"
  admin_list_lines
  username="$(trim "$(ui_prompt '\nAccount name: ' '')")"
  [[ -n "$username" ]] || return 1
  if ! ui_confirm_phrase REMOVE "Remove the administrator ${username}?"; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  admin_remove "$username"
}

admins_password_flow() {
  local username
  need_root || return 1
  admin_require admins.manage || return 1
  ui_title "Change a password"
  admin_list_lines
  username="$(trim "$(ui_prompt '\nAccount name: ' '')")"
  [[ -n "$username" ]] || return 1
  admin_set_password "$username"
}

admins_role_flow() {
  local username role choice index=0
  need_root || return 1
  admin_require admins.manage || return 1
  ui_title "Change a role"
  admin_list_lines
  username="$(trim "$(ui_prompt '\nAccount name: ' '')")"
  [[ -n "$username" ]] || return 1
  ui_title "Role"
  while IFS= read -r role; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$role"
  done < <(admin_roles)
  choice="$(ui_menu_choice)"
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  role="$(admin_roles | sed -n "${choice}p")"
  [[ -n "$role" ]] || return 1
  admin_set_role "$username" "$role"
}

admins_permissions_flow() {
  local permission
  ui_title "Permissions defined by the project"
  printf 'A role grants a set of these. A custom role picks from this list.\n\n'
  while IFS= read -r permission; do
    printf '  %s\n' "$permission"
  done < <(printf '%s\n' "${ADMIN_PERMISSIONS[@]}")
  printf '\nRoles:\n'
  while IFS= read -r permission; do
    printf '  %-16s %s\n' "$permission" "$(admin_role_permissions "$permission" | tr '\n' ' ')"
  done < <(admin_roles)
  pause
}

admins_menu() {
  local choice
  while true; do
    ui_title "Admins"
    admins_status
    printf '\n'
    if admin_has_permission admins.manage; then
      printf '1) Add an administrator\n'
      printf '2) Remove an administrator\n'
      printf '3) Change a password\n'
      printf '4) Change a role\n'
    fi
    printf '5) Show the permissions and roles\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      admin_has_permission admins.manage || {
        warn "This account cannot manage administrators."
        continue
      }
      admins_add_flow || true
      pause
      ;;
    2)
      admin_has_permission admins.manage || {
        warn "This account cannot manage administrators."
        continue
      }
      admins_remove_flow || true
      pause
      ;;
    3)
      admin_has_permission admins.manage || {
        warn "This account cannot manage administrators."
        continue
      }
      admins_password_flow || true
      pause
      ;;
    4)
      admin_has_permission admins.manage || {
        warn "This account cannot manage administrators."
        continue
      }
      admins_role_flow || true
      pause
      ;;
    5) admins_permissions_flow ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

admins_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  list) admin_list_lines ;;
  status) admins_status ;;
  permissions) printf '%s\n' "${ADMIN_PERMISSIONS[@]}" ;;
  roles)
    local role
    while IFS= read -r role; do
      printf '%-16s %s\n' "$role" "$(admin_role_permissions "$role" | tr '\n' ' ')"
    done < <(admin_roles)
    ;;
  add)
    admin_require admins.manage || return 1
    admin_add "${1:?account name is required}" "${2:?role is required}" "${3:-}"
    ;;
  remove)
    admin_require admins.manage || return 1
    need_root || return 1
    admin_remove "${1:?account name is required}"
    ;;
  passwd)
    admin_require admins.manage || return 1
    need_root || return 1
    admin_set_password "${1:?account name is required}"
    ;;
  role)
    admin_require admins.manage || return 1
    need_root || return 1
    admin_set_role "${1:?account name is required}" "${2:?role is required}"
    ;;
  check)
    local permission="${1:?permission is required}"
    if admin_has_permission "$permission"; then
      printf 'allowed\n'
      return 0
    fi
    printf 'denied\n'
    return 1
    ;;
  *)
    err "Unknown admin command: ${command:-<none>}"
    printf 'Admin commands: list, status, permissions, roles, add, remove, passwd, role, check\n'
    return 2
    ;;
  esac
}
