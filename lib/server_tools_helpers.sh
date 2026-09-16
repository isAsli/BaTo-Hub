#!/usr/bin/env bash
set -Eeuo pipefail

# Server hardening primitives.
#
# Everything in this file changes the operating system rather than a panel, so
# each operation follows the same shape: it prints what it will change, asks for
# confirmation, and reports exactly what happened. Two rules are enforced here:
#
#   - an existing firewall rule is never replaced or removed without the
#     operator confirming that specific rule;
#   - UFW is never turned off while the administrator is connected over SSH on a
#     port that UFW is not configured to allow, because that would cut the
#     session that asked for the change.
#
# Files written outside the installation directory are the minimum BaToHub needs:
# one sysctl drop-in, one limits drop-in and, for fail2ban, a jail drop-in. Each
# one is named after BaToHub and is removed again by the revert entry.

SERVER_TOOLS_LOG="${LOG_DIR}/server-tools.log"
BATOHUB_SYSCTL_FILE="/etc/sysctl.d/99-batohub.conf"
BATOHUB_LIMITS_FILE="/etc/security/limits.d/99-batohub.conf"
BATOHUB_FAIL2BAN_JAIL="/etc/fail2ban/jail.d/batohub.local"
BATOHUB_CONNTRACK_KEY="net.netfilter.nf_conntrack_max"

server_tools_log() {
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*" >>"$SERVER_TOOLS_LOG" 2>/dev/null || true
  log "SERVER-TOOLS $*"
}

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------

ufw_available() { need_cmd ufw; }

ufw_status_text() {
  ufw_available || {
    warn "ufw is not installed."
    return 1
  }
  ufw status verbose 2>/dev/null
}

ufw_is_active() {
  ufw_available || return 1
  ufw status 2>/dev/null | grep -q '^Status: active'
}

# The local port of the SSH session this command runs in. It is used to refuse an
# operation that would cut the session.
ssh_session_port() {
  local connection="${SSH_CONNECTION:-}"
  [[ -n "$connection" ]] || return 1
  # shellcheck disable=SC2086
  set -- $connection
  [[ "$#" -ge 4 ]] || return 1
  printf '%s\n' "$4"
}

ufw_port_allowed() {
  local port="$1" rules
  ufw_available || return 1
  rules="$(ufw status 2>/dev/null || true)"
  grep -Eq "^${port}(/tcp)?[[:space:]]+ALLOW" <<<"$rules"
}

# Refuses to disable UFW when the SSH session that asked for it is not allowed by
# the current rules, because the session would be terminated by the change.
ufw_disable_guard() {
  local port
  if ! port="$(ssh_session_port)"; then
    return 0
  fi
  if ufw_port_allowed "$port"; then
    printf 'The SSH port of this session (%s) is allowed by the current rules.\n' "$port"
    return 0
  fi
  err "This session runs over SSH on port ${port}, which the current UFW rules do not allow."
  err "Disabling the firewall would end this session before the change completes."
  err "Allow port ${port} first, or run this from a console."
  return 1
}

ufw_show_plan() {
  local action="$1"
  printf 'Planned change:\n'
  printf '  ufw %s\n' "$action"
}

ufw_apply_rule() {
  local rule_args="$1" description="$2"
  ufw_available || return 1
  ufw_show_plan "$rule_args"
  printf '\nCurrent rules:\n'
  ufw status numbered 2>/dev/null || true
  printf '\n'
  if ! ui_confirm "Apply: ${description}?"; then
    printf 'Nothing was changed. The existing rules were not touched.\n'
    return 0
  fi
  # shellcheck disable=SC2086
  if ! ufw $rule_args >>"${LOG_FILE}" 2>&1; then
    err "The firewall command failed. Output: ${LOG_FILE}"
    return 1
  fi
  server_tools_log "ufw ${rule_args}"
  ok "Firewall rule applied: ${description}"
  return 0
}

ufw_toggle() {
  local enable="$1"
  ufw_available || return 1
  if [[ "$enable" == "0" ]]; then
    ufw_disable_guard || return 1
    ufw_show_plan disable
  else
    ufw_show_plan enable
  fi
  printf '\n'
  if ! ui_confirm "Apply this change?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  if ! ufw "$([[ "$enable" == "1" ]] && printf enable || printf disable)" >>"${LOG_FILE}" 2>&1; then
    err "The firewall command failed. Output: ${LOG_FILE}"
    return 1
  fi
  server_tools_log "ufw $([[ "$enable" == "1" ]] && printf enable || printf disable)"
  ok "The firewall state was changed."
  return 0
}

# ---------------------------------------------------------------------------
# Fail2ban
# ---------------------------------------------------------------------------

fail2ban_available() { need_cmd fail2ban-client; }

fail2ban_install_packages() {
  local os
  os="$(os_id)"
  case "$os" in
  ubuntu | debian) ;;
  *)
    err "fail2ban is not installed and automatic installation is only defined for Ubuntu and Debian."
    return 1
    ;;
  esac
  printf 'Planned change: install the fail2ban package.\n\n'
  if ! ui_confirm "Install fail2ban?"; then
    printf 'Nothing was installed.\n'
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  if ! apt-get update -qq >>"${LOG_FILE}" 2>&1; then
    err "apt-get update failed. Output: ${LOG_FILE}"
    return 1
  fi
  if ! apt-get install -y -qq fail2ban >>"${LOG_FILE}" 2>&1; then
    err "Installing fail2ban failed. Output: ${LOG_FILE}"
    return 1
  fi
  server_tools_log "fail2ban installed"
  ok "fail2ban was installed."
  return 0
}

fail2ban_jails() {
  fail2ban_available || {
    warn "fail2ban is not installed."
    return 1
  }
  fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' '\n' |
    sed 's/^[[:space:]]*//' | grep -v '^$' || true
}

fail2ban_banned_ips() {
  local jail
  local found=0
  while IFS= read -r jail; do
    [[ -n "$jail" ]] || continue
    found=1
    printf '%s:\n' "$jail"
    fail2ban-client status "$jail" 2>/dev/null | sed -n 's/.*Banned IP list:[[:space:]]*//p' | tr ' ' '\n' |
      grep -v '^$' | sed 's/^/  /' || true
  done < <(fail2ban_jails)
  if [[ "$found" -eq 0 ]]; then
    printf 'No jail is active.\n'
  fi
  return 0
}

# Writes one jail drop-in for the services BaToHub manages. An existing drop-in
# of the same name is shown first and is only replaced after confirmation.
fail2ban_write_jail() {
  local jail="${1:-sshd}" maxretry="${2:-5}" bantime="${3:-1h}"
  fail2ban_available || return 1
  need_root || return 1
  printf 'Planned change: write %s with jail %s, maxretry %s, bantime %s.\n' \
    "$BATOHUB_FAIL2BAN_JAIL" "$jail" "$maxretry" "$bantime"
  if [[ -f "$BATOHUB_FAIL2BAN_JAIL" ]]; then
    printf '\nThe file already exists and will be replaced:\n'
    sed 's/^/  /' "$BATOHUB_FAIL2BAN_JAIL"
  fi
  printf '\n'
  if ! ui_confirm "Write this jail configuration?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  install -d -m 0755 -o root -g root "$(dirname "$BATOHUB_FAIL2BAN_JAIL")"
  atomic_write "$BATOHUB_FAIL2BAN_JAIL" 0644 "$(printf '# Written by BaToHub. Remove this file to revert.\n[%s]\nenabled = true\nmaxretry = %s\nbantime = %s\n' "$jail" "$maxretry" "$bantime")"
  server_tools_log "fail2ban jail written jail=${jail} maxretry=${maxretry} bantime=${bantime}"
  ok "The jail configuration was written."
  return 0
}

fail2ban_restart() {
  fail2ban_available || return 1
  need_root || return 1
  if service_registered fail2ban; then
    if ! run_logged "restart fail2ban" systemctl restart fail2ban; then
      err "fail2ban did not restart. Inspect: journalctl -u fail2ban -n 50"
      return 1
    fi
    ok "fail2ban restarted."
    return 0
  fi
  warn "The fail2ban service is not registered with systemd."
  return 1
}

fail2ban_unban() {
  local ip="$1" jail
  fail2ban_available || return 1
  need_root || return 1
  valid_ipv4 "$ip" || {
    err "Invalid IPv4 address: $ip"
    return 1
  }
  local unbanned=0
  while IFS= read -r jail; do
    [[ -n "$jail" ]] || continue
    if fail2ban-client set "$jail" unbanip "$ip" >>"${LOG_FILE}" 2>&1; then
      unbanned=1
    fi
  done < <(fail2ban_jails)
  if [[ "$unbanned" -eq 0 ]]; then
    warn "The address ${ip} was not banned in any jail."
    return 1
  fi
  server_tools_log "fail2ban unban ip=${ip}"
  ok "The address ${ip} was unbanned."
  return 0
}

# ---------------------------------------------------------------------------
# Kernel parameters
# ---------------------------------------------------------------------------

sysctl_get() {
  local key="$1"
  [[ -n "$key" ]] || return 1
  if need_cmd sysctl; then
    sysctl -n "$key" 2>/dev/null || true
    return 0
  fi
  local node="/proc/sys/${key//./\/}"
  [[ -r "$node" ]] && cat "$node" || true
}

sysctl_saved_values() {
  local file="$1"
  [[ -r "$file" ]] || return 1
  grep -E '^[[:space:]]*[A-Za-z0-9_.]+[[:space:]]*=' "$file" | sed 's/[[:space:]]//g' || true
}

sysctl_show_plan() {
  local file="$1" description="$2"
  local line key current target
  printf 'Planned change: %s\n' "$description"
  printf 'File: %s\n' "$file"
  printf '\nValues that will change:\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    target="${line#*=}"
    current="$(sysctl_get "$key")"
    printf '  %-40s %s -> %s\n' "$key" "${current:-unset}" "$target"
  done < <(sysctl_saved_values "$file")
  printf '\nFile contents:\n'
  sed 's/^/  /' "$file"
  printf '\n'
}

sysctl_apply_file() {
  local file="$1" description="$2"
  need_root || return 1
  [[ -s "$file" ]] || {
    err "An empty parameter file is not applied."
    return 1
  }
  sysctl_show_plan "$file" "$description"
  if ! ui_confirm "Apply these kernel parameters?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  install -d -m 0755 -o root -g root "$(dirname "$BATOHUB_SYSCTL_FILE")"
  cp -a "$file" "$BATOHUB_SYSCTL_FILE"
  if need_cmd sysctl; then
    if ! sysctl --system >>"${LOG_FILE}" 2>&1; then
      err "Applying the parameters failed. Output: ${LOG_FILE}"
      return 1
    fi
  fi
  server_tools_log "sysctl applied file=${BATOHUB_SYSCTL_FILE} description=${description}"
  ok "Kernel parameters applied from ${BATOHUB_SYSCTL_FILE}."
  return 0
}

sysctl_revert() {
  need_root || return 1
  if [[ ! -f "$BATOHUB_SYSCTL_FILE" ]]; then
    warn "No BaToHub kernel parameter file is present."
    return 1
  fi
  printf 'Planned change: remove %s and reload the kernel parameters.\n' "$BATOHUB_SYSCTL_FILE"
  printf '\nThe file currently sets:\n'
  sed 's/^/  /' "$BATOHUB_SYSCTL_FILE"
  printf '\n'
  if ! ui_confirm "Remove the BaToHub kernel parameters?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  rm -f -- "$BATOHUB_SYSCTL_FILE"
  if need_cmd sysctl; then
    sysctl --system >>"${LOG_FILE}" 2>&1 || warn "Reloading the parameters returned a non-zero status."
  fi
  server_tools_log "sysctl reverted"
  ok "The BaToHub kernel parameter file was removed."
  return 0
}

# The standard profile BaToHub applies. Every value is named here, so nothing is
# copied from an unknown source.
sysctl_bbr_profile_file() {
  local target="$1"
  atomic_write "$target" 0644 "# Written by BaToHub: BBR congestion control.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
"
}

sysctl_tuning_profile_file() {
  local target="$1"
  atomic_write "$target" 0644 "# Written by BaToHub: TCP and socket tuning profile.
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=8192
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=10240 65000
"
}

# ---------------------------------------------------------------------------
# Limits
# ---------------------------------------------------------------------------

limits_show() {
  printf 'Process limits (ulimit -n): %s\n' "$(ulimit -n 2>/dev/null || printf unknown)"
  printf 'Limit drop-in: %s\n' "$BATOHUB_LIMITS_FILE"
  if [[ -r "$BATOHUB_LIMITS_FILE" ]]; then
    printf '\nBaToHub limit entries:\n'
    sed 's/^/  /' "$BATOHUB_LIMITS_FILE"
  else
    printf 'No BaToHub limit drop-in is present.\n'
  fi
  printf '\nConnection tracking:\n'
  printf '  %s = %s\n' "$BATOHUB_CONNTRACK_KEY" "$(sysctl_get "$BATOHUB_CONNTRACK_KEY")"
  if [[ -r /proc/sys/net/netfilter/nf_conntrack_count ]]; then
    printf '  current tracked connections = %s\n' "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || printf unknown)"
  fi
  return 0
}

limits_write_file_descriptors() {
  local hard="${1:-1048576}" soft="${2:-1048576}" target
  [[ "$hard" =~ ^[0-9]+$ && "$soft" =~ ^[0-9]+$ ]] || {
    err "The file descriptor limits must be numbers."
    return 1
  }
  target="$(mktemp_file limits)"
  atomic_write "$target" 0644 "# Written by BaToHub: file descriptor limits.
* soft nofile ${soft}
* hard nofile ${hard}
root soft nofile ${soft}
root hard nofile ${hard}
"
  need_root || return 1
  printf 'Planned change: raise the file descriptor limits.\n'
  printf 'File: %s\n' "$BATOHUB_LIMITS_FILE"
  printf '\nNew contents:\n'
  sed 's/^/  /' "$target"
  printf '\nA new login session is required for the limits to take effect.\n\n'
  if ! ui_confirm "Apply these limits?"; then
    rm -f -- "$target"
    printf 'Nothing was changed.\n'
    return 0
  fi
  install -d -m 0755 -o root -g root "$(dirname "$BATOHUB_LIMITS_FILE")"
  mv -f -- "$target" "$BATOHUB_LIMITS_FILE"
  chmod 0644 "$BATOHUB_LIMITS_FILE"
  chown root:root "$BATOHUB_LIMITS_FILE" 2>/dev/null || true
  server_tools_log "limits written file=${BATOHUB_LIMITS_FILE} soft=${soft} hard=${hard}"
  ok "The file descriptor limits were written."
  return 0
}

# ---------------------------------------------------------------------------
# Time and timezone
# ---------------------------------------------------------------------------

time_status_lines() {
  printf 'Current time: %s\n' "$(date '+%F %T %Z (%z)')"
  printf 'Timezone file: %s\n' "$(cat /etc/timezone 2>/dev/null || printf 'not present')"
  if need_cmd timedatectl; then
    timedatectl status 2>/dev/null | sed -n 's/^[[:space:]]*/  /p' | head -n 12
  else
    printf 'timedatectl is not available; showing the clock state only.\n'
  fi
  if need_cmd chronyc; then
    printf '\nchrony tracking:\n'
    chronyc tracking 2>/dev/null | sed 's/^/  /' | head -n 8 || true
  fi
  return 0
}

time_set_timezone() {
  local zone="$1"
  need_root || return 1
  [[ -n "$zone" ]] || {
    err "A timezone is required, for example Europe/Berlin."
    return 1
  }
  if [[ ! -r "/usr/share/zoneinfo/${zone}" ]]; then
    err "Unknown timezone: ${zone}"
    return 1
  fi
  printf 'Planned change: set the system timezone to %s.\n' "$zone"
  printf 'Current timezone: %s\n\n' "$(date '+%Z %z')"
  if ! ui_confirm "Set the timezone to ${zone}?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  if need_cmd timedatectl; then
    if ! timedatectl set-timezone "$zone" >>"${LOG_FILE}" 2>&1; then
      err "Setting the timezone failed. Output: ${LOG_FILE}"
      return 1
    fi
  else
    ln -sfn "/usr/share/zoneinfo/${zone}" /etc/localtime
    printf '%s\n' "$zone" >/etc/timezone
  fi
  server_tools_log "timezone set zone=${zone}"
  ok "The timezone is now $(date '+%Z %z')."
  return 0
}

time_enable_ntp() {
  need_root || return 1
  printf 'Planned change: enable network time synchronisation.\n\n'
  if need_cmd timedatectl; then
    printf 'Current state:\n'
    timedatectl status 2>/dev/null | sed -n 's/^[[:space:]]*/  /p' | head -n 8
    printf '\n'
  fi
  if ! ui_confirm "Enable NTP synchronisation?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  if need_cmd timedatectl; then
    if ! timedatectl set-ntp true >>"${LOG_FILE}" 2>&1; then
      err "Enabling NTP failed. Output: ${LOG_FILE}"
      return 1
    fi
  elif service_registered systemd-timesyncd; then
    systemctl enable --now systemd-timesyncd >>"${LOG_FILE}" 2>&1 || {
      err "Enabling the time service failed. Output: ${LOG_FILE}"
      return 1
    }
  else
    err "Neither timedatectl nor a time synchronisation service is available."
    return 1
  fi
  server_tools_log "ntp enabled"
  ok "Network time synchronisation is enabled."
  return 0
}
