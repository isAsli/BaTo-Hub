#!/usr/bin/env bash
set -Eeuo pipefail

# The Server Tools section: firewall, fail2ban, kernel parameters, limits and
# time. Every entry shows the planned change before it applies anything.

server_tools_firewall_menu() {
  local choice port address
  while true; do
    ui_title "Firewall (ufw)"
    if ufw_available; then
      ufw status verbose 2>/dev/null | head -n 30 || true
    else
      warn "ufw is not installed."
    fi
    printf '\n'
    printf '1) Open a port\n'
    printf '2) Close a port\n'
    printf '3) Allow a port only from one address\n'
    printf '4) Enable the firewall\n'
    printf '5) Disable the firewall\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      port="$(trim "$(ui_prompt 'Port: ' '')")"
      if [[ "$port" =~ ^[0-9]{1,5}$ ]]; then
        ufw_apply_rule "allow ${port}/tcp" "allow TCP port ${port}" || true
      elif [[ "$port" =~ ^[0-9]{1,5}/[a-z]+$ ]]; then
        ufw_apply_rule "allow ${port}" "allow ${port}" || true
      else
        warn "Enter a port number, optionally with a protocol such as 443/tcp."
      fi
      pause
      ;;
    2)
      port="$(trim "$(ui_prompt 'Port to close (closing removes the rule that allows it): ' '')")"
      if [[ "$port" =~ ^[0-9]{1,5}(/[a-z]+)?$ ]]; then
        ufw_apply_rule "delete allow ${port}" "close port ${port}" || true
      else
        warn "Enter a port number, optionally with a protocol such as 443/tcp."
      fi
      pause
      ;;
    3)
      address="$(trim "$(ui_prompt 'Address that may connect: ' '')")"
      port="$(trim "$(ui_prompt 'Port: ' '')")"
      if valid_ipv4 "$address" && [[ "$port" =~ ^[0-9]{1,5}$ ]]; then
        ufw_apply_rule "allow from ${address} to any port ${port} proto tcp" \
          "allow ${address} to TCP port ${port}" || true
      else
        warn "Enter an IPv4 address and a port number."
      fi
      pause
      ;;
    4)
      ufw_toggle 1 || true
      pause
      ;;
    5)
      ufw_toggle 0 || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

server_tools_fail2ban_menu() {
  local choice ip jail
  while true; do
    ui_title "Fail2ban"
    if fail2ban_available; then
      printf 'Active jails: %s\n' "$(fail2ban_jails | tr '\n' ' ')"
    else
      warn "fail2ban is not installed."
    fi
    printf '\n'
    printf '1) Show banned addresses\n'
    printf '2) Unban an address\n'
    printf '3) Write a jail configuration\n'
    printf '4) Restart fail2ban\n'
    printf '5) Install fail2ban\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      fail2ban_banned_ips || true
      pause
      ;;
    2)
      ip="$(trim "$(ui_prompt 'Address to unban: ' '')")"
      fail2ban_unban "$ip" || true
      pause
      ;;
    3)
      jail="$(trim "$(ui_prompt 'Jail name [sshd]: ' 'sshd')")"
      fail2ban_write_jail "${jail:-sshd}" || true
      pause
      ;;
    4)
      fail2ban_restart || true
      pause
      ;;
    5)
      fail2ban_install_packages || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

server_tools_kernel_menu() {
  local choice tmp
  while true; do
    ui_title "BBR and TCP tuning"
    printf 'Congestion control: %s\n' "$(sysctl_get net.ipv4.tcp_congestion_control)"
    printf 'Queue discipline:   %s\n' "$(sysctl_get net.core.default_qdisc)"
    printf 'BaToHub parameter file: %s\n' "$BATOHUB_SYSCTL_FILE"
    printf '\n'
    printf '1) Enable BBR and the low latency profile\n'
    printf '2) Apply the standard TCP tuning profile\n'
    printf '3) Show the current settings\n'
    printf '4) Revert to the defaults\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      tmp="$(mktemp_file bbr)"
      sysctl_bbr_profile_file "$tmp"
      sysctl_apply_file "$tmp" "enable BBR" || true
      rm -f -- "$tmp"
      pause
      ;;
    2)
      tmp="$(mktemp_file tuning)"
      sysctl_tuning_profile_file "$tmp"
      sysctl_apply_file "$tmp" "apply the TCP tuning profile" || true
      rm -f -- "$tmp"
      pause
      ;;
    3)
      for key in net.ipv4.tcp_congestion_control net.core.default_qdisc net.core.somaxconn \
        net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_fin_timeout net.ipv4.tcp_tw_reuse; do
        printf '%-40s %s\n' "$key" "$(sysctl_get "$key")"
      done
      pause
      ;;
    4)
      sysctl_revert || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

server_tools_limits_menu() {
  local choice soft hard conntrack
  while true; do
    ui_title "System limits"
    limits_show
    printf '\n1) Raise the file descriptor limits\n'
    printf '2) Raise the connection tracking limit\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      soft="$(trim "$(ui_prompt 'Soft limit [1048576]: ' '1048576')")"
      hard="$(trim "$(ui_prompt 'Hard limit [1048576]: ' '1048576')")"
      limits_write_file_descriptors "${hard:-1048576}" "${soft:-1048576}" || true
      pause
      ;;
    2)
      conntrack="$(trim "$(ui_prompt 'nf_conntrack_max [262144]: ' '262144')")"
      if [[ ! "$conntrack" =~ ^[0-9]+$ ]]; then
        warn "Enter a number."
      else
        local tmp
        tmp="$(mktemp_file conntrack)"
        atomic_write "$tmp" 0644 "# Written by BaToHub: connection tracking limit.
${BATOHUB_CONNTRACK_KEY}=${conntrack}
"
        sysctl_apply_file "$tmp" "raise the connection tracking limit" || true
        rm -f -- "$tmp"
      fi
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

server_tools_time_menu() {
  local choice zone
  while true; do
    ui_title "Timezone and NTP"
    time_status_lines
    printf '\n1) Set the timezone\n'
    printf '2) Enable NTP synchronisation\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1)
      zone="$(trim "$(ui_prompt 'Timezone (for example Europe/Berlin): ' '')")"
      time_set_timezone "$zone" || true
      pause
      ;;
    2)
      time_enable_ntp || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

server_tools_menu() {
  local choice
  while true; do
    ui_title "Server Tools"
    printf '1) Firewall (ufw)\n'
    printf '2) Fail2ban\n'
    printf '3) BBR and TCP tuning\n'
    printf '4) System limits\n'
    printf '5) Timezone and NTP\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) server_tools_firewall_menu ;;
    2) server_tools_fail2ban_menu ;;
    3) server_tools_kernel_menu ;;
    4) server_tools_limits_menu ;;
    5) server_tools_time_menu ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

# Non-interactive entry. Every mutating command still prints the planned change;
# the non-interactive form is meant for an operator who scripted the change
# deliberately, so it applies without a prompt but records it in the log.
server_tools_cli() {
  local command="${1:-}"
  shift || true
  case "$command" in
  firewall)
    case "${1:-}" in
    status)
      ufw_status_text || return 1
      ;;
    allow-port)
      need_root || return 1
      local port="${2:-}"
      [[ "$port" =~ ^[0-9]{1,5}(/[a-z]+)?$ ]] || {
        err "Usage: BaToHub --server firewall allow-port <port>"
        return 2
      }
      ufw_apply_rule "allow ${port}" "allow ${port}"
      ;;
    deny-port)
      need_root || return 1
      local port="${2:-}"
      [[ "$port" =~ ^[0-9]{1,5}(/[a-z]+)?$ ]] || {
        err "Usage: BaToHub --server firewall deny-port <port>"
        return 2
      }
      ufw_apply_rule "delete allow ${port}" "close port ${port}"
      ;;
    allow-from)
      need_root || return 1
      local address="${2:-}" port="${3:-}"
      valid_ipv4 "$address" && [[ "$port" =~ ^[0-9]{1,5}$ ]] || {
        err "Usage: BaToHub --server firewall allow-from <address> <port>"
        return 2
      }
      ufw_apply_rule "allow from ${address} to any port ${port} proto tcp" \
        "allow ${address} to TCP port ${port}"
      ;;
    enable | disable)
      need_root || return 1
      ufw_toggle "$([[ "${1}" == enable ]] && printf 1 || printf 0)"
      ;;
    *)
      err "Firewall commands: status, allow-port, deny-port, allow-from, enable, disable"
      return 2
      ;;
    esac
    ;;
  fail2ban)
    case "${1:-}" in
    jails) fail2ban_jails ;;
    banned) fail2ban_banned_ips ;;
    status)
      fail2ban_available || return 1
      fail2ban-client status
      ;;
    unban)
      need_root || return 1
      fail2ban_unban "${2:?address is required}"
      ;;
    jail)
      need_root || return 1
      fail2ban_write_jail "${2:-sshd}" "${3:-5}" "${4:-1h}"
      ;;
    restart)
      need_root || return 1
      fail2ban_restart
      ;;
    install)
      need_root || return 1
      fail2ban_install_packages
      ;;
    *)
      err "Fail2ban commands: status, jails, banned, unban, jail, restart, install"
      return 2
      ;;
    esac
    ;;
  bbr)
    case "${1:-}" in
    status)
      printf '%-40s %s\n' net.ipv4.tcp_congestion_control "$(sysctl_get net.ipv4.tcp_congestion_control)"
      printf '%-40s %s\n' net.core.default_qdisc "$(sysctl_get net.core.default_qdisc)"
      ;;
    enable)
      need_root || return 1
      local tmp
      tmp="$(mktemp_file bbr)"
      sysctl_bbr_profile_file "$tmp"
      sysctl_apply_file "$tmp" "enable BBR"
      local status=$?
      rm -f -- "$tmp"
      return "$status"
      ;;
    tuning)
      need_root || return 1
      local tmp
      tmp="$(mktemp_file tuning)"
      sysctl_tuning_profile_file "$tmp"
      sysctl_apply_file "$tmp" "apply the TCP tuning profile"
      local status=$?
      rm -f -- "$tmp"
      return "$status"
      ;;
    revert)
      need_root || return 1
      sysctl_revert
      ;;
    *)
      err "BBR commands: status, enable, tuning, revert"
      return 2
      ;;
    esac
    ;;
  limits)
    case "${1:-}" in
    show) limits_show ;;
    nofile)
      need_root || return 1
      limits_write_file_descriptors "${3:-1048576}" "${2:-1048576}"
      ;;
    conntrack)
      need_root || return 1
      local tmp
      tmp="$(mktemp_file conntrack)"
      atomic_write "$tmp" 0644 "# Written by BaToHub: connection tracking limit.
${BATOHUB_CONNTRACK_KEY}=${2:?value is required}
"
      sysctl_apply_file "$tmp" "raise the connection tracking limit"
      local status=$?
      rm -f -- "$tmp"
      return "$status"
      ;;
    *)
      err "Limit commands: show, nofile <soft> <hard>, conntrack <value>"
      return 2
      ;;
    esac
    ;;
  time)
    case "${1:-}" in
    status) time_status_lines ;;
    timezone)
      need_root || return 1
      time_set_timezone "${2:?timezone is required}"
      ;;
    ntp)
      need_root || return 1
      time_enable_ntp
      ;;
    *)
      err "Time commands: status, timezone <zone>, ntp"
      return 2
      ;;
    esac
    ;;
  *)
    err "Unknown server command: ${command:-<none>}"
    printf 'Server commands: firewall, fail2ban, bbr, limits, time\n'
    return 2
    ;;
  esac
}
