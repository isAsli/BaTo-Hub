#!/usr/bin/env bash
set -Eeuo pipefail

# Administrators, roles and permissions.
#
# The root user is always an administrator with full access; the accounts below
# are additional. An account is one line in ${CONFIG_DIR}/admins.conf, which is
# kept at mode 0600:
#
#   username:role:password-hash:permission,permission,...
#
# The password is stored as a SHA-512 crypt hash produced by openssl. The hash is
# written with the file, never printed, and never logged. Every action that a
# permission gate allows is appended to ${LOG_DIR}/admins.log together with the
# acting account and a timestamp.
#
# A permission is only ever checked through admin_require, so a new command
# cannot forget the check: the entry point of every section calls it before the
# section runs.

ADMIN_CONF="${CONFIG_DIR}/admins.conf"
ADMIN_LOG="${LOG_DIR}/admins.log"

# Every permission the project defines. The list is the contract between the
# roles below and the commands that check it.
ADMIN_PERMISSIONS=(
  panels.view
  panels.install
  panels.update
  panels.uninstall
  ssl.issue
  ssl.renew
  ssl.revoke
  templates.apply
  templates.remove
  backup.create
  backup.restore
  backup.delete
  servers.view
  servers.add
  servers.remove
  tools.run
  alerts.view
  alerts.configure
  admins.manage
  settings.edit
  migration.run
  update.run
)

admin_permission_valid() {
  local permission
  for permission in "${ADMIN_PERMISSIONS[@]}"; do
    [[ "$permission" == "${1:-}" ]] && return 0
  done
  return 1
}

admin_roles() { printf '%s\n' full panel-manager ssl-manager backup-manager read-only custom; }

admin_role_valid() {
  local role
  while IFS= read -r role; do
    [[ "$role" == "${1:-}" ]] && return 0
  done < <(admin_roles)
  return 1
}

# The permissions a built-in role grants.
admin_role_permissions() {
  case "${1:-}" in
  full) printf '%s\n' "${ADMIN_PERMISSIONS[@]}" ;;
  panel-manager)
    printf '%s\n' panels.view panels.install panels.update panels.uninstall \
      ssl.issue ssl.renew ssl.revoke templates.apply templates.remove \
      backup.create alerts.view migration.run
    ;;
  ssl-manager) printf '%s\n' panels.view ssl.issue ssl.renew ssl.revoke alerts.view ;;
  backup-manager) printf '%s\n' panels.view backup.create backup.restore backup.delete alerts.view ;;
  read-only) printf '%s\n' panels.view servers.view alerts.view ;;
  custom) return 0 ;;
  *) return 1 ;;
  esac
  return 0
}

admin_username_valid() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9._-]{1,31}$ ]]
}

admin_config_ensure() {
  install -d -m 0750 -o root -g root "$CONFIG_DIR"
  if [[ ! -f "$ADMIN_CONF" ]]; then
    atomic_write "$ADMIN_CONF" 0600 "# BaToHub administrators.
# Format: username:role:password-hash:permission,permission,...
# The root user always has full access and is not listed here.
# Manage this file with: BaToHub --admin add|remove|passwd|role|list
"
  fi
  harden_file "$ADMIN_CONF" 0600
  return 0
}

# The root account always exists with full access; it is not an entry in the
# account file, so it is answered directly instead of being looked up.
admin_exists() {
  local line
  [[ "${1:-}" == "root" ]] && return 0
  [[ -r "$ADMIN_CONF" ]] || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in \#*) continue ;; esac
    [[ "${line%%:*}" == "${1:-}" ]] && return 0
  done <"$ADMIN_CONF"
  return 1
}

# The root account is not stored in the account file, so it is never removed,
# re-roled or given a stored password by the commands below.
admin_root_guard() {
  if [[ "${1:-}" == "root" ]]; then
    err "The root account is built in and cannot be changed through this command."
    return 1
  fi
  return 0
}

admin_line() {
  local line
  [[ -r "$ADMIN_CONF" ]] || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in \#*) continue ;; esac
    if [[ "${line%%:*}" == "${1:-}" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done <"$ADMIN_CONF"
  return 1
}

admin_field() {
  local username="$1" index="$2" line
  line="$(admin_line "$username")" || return 1
  printf '%s\n' "$line" | cut -d: -f"$index"
}

# Reads a password for an account. The menu prompts; a headless run reads one line
# from standard input, so the password never reaches the process list and a script
# can create an account without a terminal.
admin_read_password() {
  local username="$1" password=""
  if [[ "$INTERACTIVE" == 1 ]]; then
    password="$(ui_prompt "Password for ${username}: " '')"
  else
    IFS= read -r password || password=""
  fi
  printf '%s\n' "$password"
}

admin_hash_password() {
  local password="$1"
  need_cmd openssl || {
    err "openssl is required to hash an administrator password."
    return 1
  }
  printf '%s' "$password" | openssl passwd -6 -stdin 2>/dev/null
}

# Verifies a password against the stored SHA-512 crypt hash. The candidate
# password is passed through standard input, so it never appears in the process
# list.
admin_verify_password() {
  local username="$1" password="$2" stored salt candidate
  stored="$(admin_field "$username" 3)" || return 1
  [[ -n "$stored" ]] || return 1
  salt="$(printf '%s' "$stored" | cut -d'$' -f3)"
  [[ -n "$salt" ]] || return 1
  candidate="$(printf '%s' "$password" | openssl passwd -6 -salt "$salt" -stdin 2>/dev/null)"
  [[ -n "$candidate" && "$candidate" == "$stored" ]]
}

admin_write() {
  local username="$1" role="$2" hash="$3" permissions="$4" tmp
  admin_config_ensure || return 1
  tmp="$(mktemp_file admins)"
  if [[ -r "$ADMIN_CONF" ]]; then
    grep -v "^${username}:" "$ADMIN_CONF" >"$tmp" || true
  fi
  printf '%s:%s:%s:%s\n' "$username" "$role" "$hash" "$permissions" >>"$tmp"
  chmod 0600 "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$ADMIN_CONF"
  harden_file "$ADMIN_CONF" 0600
  return 0
}

admin_permissions_of() {
  local username="$1" role permissions
  role="$(admin_field "$username" 2)" || return 1
  permissions="$(admin_field "$username" 4 || true)"
  if [[ -n "$permissions" ]]; then
    printf '%s\n' "$permissions" | tr ',' '\n' | grep -v '^$' || true
    return 0
  fi
  admin_role_permissions "$role"
}

admin_add() {
  local username="$1" role="$2" permissions="${3:-}" password password2 hash line="" permission
  need_root || return 1
  admin_username_valid "$username" || {
    err "Invalid administrator name: ${username}"
    err "Use lower case letters, digits, dot, dash and underscore."
    return 1
  }
  admin_role_valid "$role" || {
    err "Invalid role: ${role}"
    err "Roles: $(admin_roles | tr '\n' ' ')"
    return 1
  }
  if admin_exists "$username"; then
    err "The administrator ${username} already exists."
    return 1
  fi
  if [[ "$role" == "custom" ]]; then
    if [[ -z "$permissions" ]]; then
      while IFS= read -r permission; do
        printf '  %s\n' "$permission"
      done < <(printf '%s\n' "${ADMIN_PERMISSIONS[@]}")
      permissions="$(trim "$(ui_prompt 'Permissions (comma separated): ' '')")"
    fi
    local item
    IFS=',' read -r -a items <<<"$permissions"
    for item in "${items[@]}"; do
      item="$(trim "$item")"
      admin_permission_valid "$item" || {
        err "Unknown permission: ${item}"
        return 1
      }
      line+="${line:+,}${item}"
    done
    [[ -n "$line" ]] || {
      err "A custom role needs at least one permission."
      return 1
    }
  fi
  password="$(admin_read_password "$username")"
  [[ -n "$password" ]] || {
    err "A password is required."
    return 1
  }
  if [[ "$INTERACTIVE" == 1 ]]; then
    password2="$(ui_prompt 'Repeat the password: ' '')"
    [[ "$password" == "$password2" ]] || {
      err "The passwords do not match."
      return 1
    }
  fi
  hash="$(admin_hash_password "$password")" || return 1
  admin_write "$username" "$role" "$hash" "$line" || return 1
  admin_log "add user=${username} role=${role}"
  ok "Administrator ${username} was created with the role ${role}."
  return 0
}

admin_remove() {
  local username="$1" tmp
  need_root || return 1
  admin_root_guard "$username" || return 1
  admin_exists "$username" || {
    err "No administrator named ${username}."
    return 1
  }
  tmp="$(mktemp_file admins)"
  grep -v "^${username}:" "$ADMIN_CONF" >"$tmp" || true
  chmod 0600 "$tmp"
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$ADMIN_CONF"
  harden_file "$ADMIN_CONF" 0600
  admin_log "remove user=${username}"
  ok "Administrator ${username} was removed."
  return 0
}

admin_set_password() {
  local username="$1" password password2 hash
  need_root || return 1
  admin_root_guard "$username" || return 1
  admin_exists "$username" || {
    err "No administrator named ${username}."
    return 1
  }
  password="$(admin_read_password "$username")"
  [[ -n "$password" ]] || {
    err "A password is required."
    return 1
  }
  if [[ "$INTERACTIVE" == 1 ]]; then
    password2="$(ui_prompt 'Repeat the password: ' '')"
    [[ "$password" == "$password2" ]] || {
      err "The passwords do not match."
      return 1
    }
  fi
  hash="$(admin_hash_password "$password")" || return 1
  admin_write "$username" "$(admin_field "$username" 2)" "$hash" "$(admin_field "$username" 4 || true)" || return 1
  admin_log "passwd user=${username}"
  ok "The password of ${username} was changed."
  return 0
}

admin_set_role() {
  local username="$1" role="$2"
  need_root || return 1
  admin_root_guard "$username" || return 1
  admin_exists "$username" || {
    err "No administrator named ${username}."
    return 1
  }
  admin_role_valid "$role" || {
    err "Invalid role: ${role}"
    return 1
  }
  admin_write "$username" "$role" "$(admin_field "$username" 3)" "" || return 1
  admin_log "role user=${username} role=${role}"
  ok "The role of ${username} is now ${role}."
  return 0
}

# The account a command runs as. Root is the built-in full administrator; when an
# account is named through BATOHUB_ADMIN its own permissions apply.
admin_current_user() {
  local user
  user="$(trim "${BATOHUB_ADMIN:-}")"
  if [[ -n "$user" ]]; then
    printf '%s\n' "$user"
    return 0
  fi
  printf 'root\n'
}

admin_current_role() {
  local user
  user="$(admin_current_user)"
  if [[ "$user" == "root" ]]; then
    printf 'full\n'
    return 0
  fi
  admin_field "$user" 2 || printf 'unknown\n'
}

admin_has_permission() {
  local permission="$1" user
  user="$(admin_current_user)"
  if [[ "$user" == "root" ]]; then
    return 0
  fi
  if ! admin_exists "$user"; then
    return 1
  fi
  if ! admin_permission_valid "$permission"; then
    err "Unknown permission: ${permission}"
    return 1
  fi
  local granted
  while IFS= read -r granted; do
    [[ "$granted" == "$permission" ]] && return 0
  done < <(admin_permissions_of "$user")
  return 1
}

# The gate every section calls before it runs. A refusal is recorded, so an
# attempt to use a command outside a role is visible in the log.
admin_require() {
  local permission="$1"
  if admin_has_permission "$permission"; then
    return 0
  fi
  err "The account $(admin_current_user) (role $(admin_current_role)) is not allowed to use this command."
  err "Required permission: ${permission}"
  admin_log "denied user=$(admin_current_user) permission=${permission}"
  return 1
}

admin_log() {
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] user=%s %s\n' "$(date '+%F %T%z')" "$(admin_current_user)" "$*" >>"$ADMIN_LOG" 2>/dev/null || true
  log "ADMIN user=$(admin_current_user) $*"
}

admin_list_lines() {
  local line username role
  printf '  %-20s %-16s %s\n' ACCOUNT ROLE PERMISSIONS
  printf '  %-20s %-16s %s\n' root full "all"
  [[ -r "$ADMIN_CONF" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in \#*) continue ;; esac
    username="${line%%:*}"
    role="$(printf '%s' "$line" | cut -d: -f2)"
    printf '  %-20s %-16s %s\n' "$username" "$role" \
      "$(admin_permissions_of "$username" | tr '\n' ' ')"
  done <"$ADMIN_CONF"
  return 0
}
