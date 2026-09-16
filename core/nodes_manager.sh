#!/usr/bin/env bash
set -Eeuo pipefail

# The Servers section: remote nodes of the panels that support them.
#
# Every panel declares its own node interface in panels/<name>/nodes/module.sh.
# This file only drives that interface, so a panel whose API differs replaces the
# function it needs in its own module and nothing here changes.

# Validates the values a caller supplies for a new node. The menu flow and the
# command line both come through here, so a value that is refused in the menu is
# refused on the command line as well.
nodes_validate_registration() {
  local panel="$1" name="$2" role="${3:-}" host="$4" port="$5" fingerprint="${6:-}"
  node_name_valid "$name" || {
    err "Invalid node name: ${name}"
    err "Use letters, digits, dot, dash and underscore."
    return 1
  }
  if node_record_exists "$panel" "$name"; then
    err "A node named ${name} is already registered for ${panel}."
    return 1
  fi
  node_role_valid "$role" || {
    err "Invalid node role: ${role}"
    return 1
  }
  if ! valid_ipv4 "$host" && ! valid_domain "$host"; then
    err "Invalid address: ${host}"
    return 1
  fi
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]]; then
    err "Invalid port: ${port}"
    return 1
  fi
  if [[ -n "$fingerprint" ]] && ! node_fingerprint_valid "$fingerprint"; then
    err "The fingerprint must be 32 colon separated byte pairs."
    return 1
  fi
  return 0
}

# Registers validated values in the panel and records them locally. The remote
# machine is not touched here: the connection bundle and the optional installer
# run afterwards, and neither of them writes to the panel.
nodes_register_node() {
  local panel="$1" name="$2" role="$3" host="$4" port="$5" fingerprint="${6:-}" tls="${7:-1}"
  node_register "$name" "$role" "$host" "$port" "$fingerprint" "$tls" || {
    err "The panel refused the node registration."
    return 1
  }
  node_record_write "$panel" "$name" \
    NODE_ROLE "$role" \
    NODE_HOST "$host" \
    NODE_PORT "$port" \
    NODE_TLS "$tls" \
    NODE_FINGERPRINT "${fingerprint:-none}" \
    NODE_ADDED_AT "$(date '+%F %T')" || return 1
  nodes_log "registered panel=${panel} node=${name} address=${host}:${port} role=${role}"
  ok "Node ${name} registered in $(panel_display_for "$panel")."
  return 0
}

# Deregisters a node in the panel and removes the local record. The remote
# machine is never modified by this step, and the record is kept when the panel
# refuses, so a failed deregistration does not lose the connection details.
nodes_remove_node() {
  local panel="$1" name="$2"
  node_panel_supports_nodes "$panel" || {
    err "Panel ${panel} does not declare node support."
    return 1
  }
  nodes_load_interface "$panel" || return 1
  node_record_exists "$panel" "$name" || {
    err "No node named ${name} is registered for ${panel}."
    return 1
  }
  if ! node_deregister "$name"; then
    err "The panel refused the deregistration; the local record was kept."
    return 1
  fi
  node_record_delete "$panel" "$name"
  nodes_log "deregistered panel=${panel} node=${name}"
  ok "Node ${name} was deregistered. The remote machine was not modified."
  return 0
}

# Loads a panel together with its node interface. The panel interface is
# validated by the loader, so a panel that declares node support but does not
# implement the node functions is reported instead of half working.
nodes_load_interface() {
  local panel="$1"
  loader_load_panel "$panel" >/dev/null 2>&1 || {
    err "Panel could not be loaded: $panel"
    return 1
  }
  panel_submodule nodes || return 1
  local fn
  for fn in node_api_available node_list node_register node_deregister node_restart node_show node_logs node_state; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
      err "Panel ${panel} does not implement the node interface: ${fn}"
      return 1
    fi
  done
  return 0
}

nodes_panel_choice() {
  local panels=() name choice index=0
  while IFS= read -r name; do
    [[ -n "$name" ]] && panels+=("$name")
  done < <(node_panels_with_nodes)
  if [[ "${#panels[@]}" -eq 0 ]]; then
    warn "No panel in this release declares node support."
    return 1
  fi
  if [[ "${#panels[@]}" -eq 1 ]]; then
    printf '%s\n' "${panels[0]}"
    return 0
  fi
  ui_title "Choose a panel"
  for name in "${panels[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$(panel_display_for "$name")"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" == 0 ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  name="${panels[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 1
  }
  printf '%s\n' "$name"
}

# The status of one node as its panel reports it. A panel that cannot be reached
# is reported as unreachable rather than as a healthy node.
node_status_line() {
  local panel="$1" name="$2" state
  if ! nodes_load_interface "$panel" >/dev/null 2>&1; then
    printf 'unreachable\n'
    return 0
  fi
  state="$(node_state "$name" 2>/dev/null || true)"
  printf '%s\n' "${state:-unknown}"
}

nodes_list_lines() {
  local filter="${1:-}" panel name host port status found=0
  while IFS=$'\t' read -r panel name; do
    [[ -n "$panel" ]] || continue
    found=1
    host="$(node_record_read "$panel" "$name" NODE_HOST)"
    port="$(node_record_read "$panel" "$name" NODE_PORT)"
    status="$(node_status_line "$panel" "$name")"
    printf '  %-10s %-18s %-22s %-14s %s\n' "$panel" "$name" "${host}:${port}" "$status" \
      "$(node_record_read "$panel" "$name" NODE_ADDED_AT)"
  done < <(node_records "$filter")
  if [[ "$found" -eq 0 ]]; then
    if [[ -n "$filter" ]]; then
      printf '  No node is registered for %s.\n' "$filter"
    else
      printf '  No node is registered.\n'
    fi
  fi
  return 0
}

nodes_list_menu() {
  ui_title "Registered nodes"
  printf '  %-10s %-18s %-22s %-14s %s\n' PANEL NODE ADDRESS STATUS REGISTERED
  nodes_list_lines
  pause
}

node_ask_name() {
  local panel="$1" name
  nodes_list_lines "$panel"
  name="$(trim "$(ui_prompt $'\nNode name: ' '')")"
  if ! node_record_exists "$panel" "$name"; then
    err "No node named ${name} is registered for ${panel}."
    return 1
  fi
  printf '%s\n' "$name"
}

nodes_add_flow() {
  local panel role host port fingerprint tls="1" name ssh_user ssh_key answer installer_url
  need_root || return 1
  panel="$(nodes_panel_choice)" || return 0
  nodes_load_interface "$panel" || return 1
  ui_title "Add a node to $(panel_display_for "$panel")"
  printf 'Panel: %s\n' "$(panel_display_for "$panel")"
  printf 'Node API: %s\n\n' "$(nodes_api_base "$panel" || printf 'not declared')"

  role="$(panel_meta_get "$panel" nodes.default_role 2>/dev/null)"
  printf 'Node roles declared by this panel:\n'
  while IFS= read -r answer; do
    [[ -n "$answer" ]] && printf '  %s\n' "$answer"
  done < <(panel_meta_list "$panel" nodes.roles 2>/dev/null || true)
  role="$(trim "$(ui_prompt "Role [${role}]: " "$role")")"
  node_role_valid "$role" || {
    err "Invalid node role: $role"
    return 1
  }

  name="$(trim "$(ui_prompt 'Node name: ' '')")"
  host="$(trim "$(ui_prompt 'Address of the remote machine: ' '')")"
  if [[ -z "$host" ]]; then
    err "An address is required."
    return 1
  fi
  port="$(trim "$(ui_prompt "Node port [$(panel_meta_get "$panel" nodes.default_node_port 2>/dev/null || printf '')]: " "$(panel_meta_get "$panel" nodes.default_node_port 2>/dev/null || printf '')")")"
  fingerprint="$(trim "$(ui_prompt 'Certificate fingerprint of the node (SHA-256, colon separated): ' '')")"
  nodes_validate_registration "$panel" "$name" "$role" "$host" "$port" "$fingerprint" || return 1

  if ! ui_confirm "Use TLS for this node?"; then
    tls="0"
  fi

  installer_url="$(nodes_node_installer_url "$panel")"

  printf '\n'
  printf 'The following will be registered in %s:\n' "$(panel_display_for "$panel")"
  printf '  role:        %s\n' "$role"
  printf '  name:        %s\n' "$name"
  printf '  address:     %s:%s\n' "$host" "$port"
  printf '  TLS:         %s\n' "$tls"
  printf '  fingerprint: %s\n' "${fingerprint:-not supplied}"
  printf '\nNo data on the remote machine is read or written by this step.\n\n'
  if ! ui_confirm 'Register this node?'; then
    printf 'Nothing was registered.\n'
    return 0
  fi

  nodes_register_node "$panel" "$name" "$role" "$host" "$port" "$fingerprint" "$tls" || return 1

  nodes_connection_bundle "$panel" "$name" "$host" "$port" "$role" "${fingerprint:-not supplied}"
  if [[ -n "$installer_url" ]] && need_cmd ssh; then
    printf '\n'
    if ui_confirm "Install the node runtime over SSH now?"; then
      ssh_user="$(trim "$(ui_prompt 'SSH user: ' 'root')")"
      ssh_key="$(trim "$(ui_prompt 'SSH private key path (leave empty for the agent): ' '')")"
      nodes_install_over_ssh "$panel" "$host" "${ssh_user:-root}" "$ssh_key"
    fi
  fi
  return 0
}

nodes_remove_flow() {
  local panel name
  need_root || return 1
  panel="$(nodes_panel_choice)" || return 0
  nodes_load_interface "$panel" || return 1
  ui_title "Remove a node from $(panel_display_for "$panel")"
  name="$(node_ask_name "$panel")" || return 0
  printf '\nThe node is deregistered from the panel and the BaToHub record is removed.\n'
  printf 'Nothing on the remote machine is deleted.\n\n'
  if ! ui_confirm_phrase REMOVE 'Deregister this node?'; then
    printf 'Nothing was removed.\n'
    return 0
  fi
  nodes_remove_node "$panel" "$name"
}

nodes_restart_flow() {
  local panel name
  need_root || return 1
  panel="$(nodes_panel_choice)" || return 0
  nodes_load_interface "$panel" || return 1
  ui_title "Restart a node of $(panel_display_for "$panel")"
  name="$(node_ask_name "$panel")" || return 0
  if ! node_restart "$name"; then
    err "The panel did not accept the restart of ${name}."
    return 1
  fi
  nodes_log "restart panel=${panel} node=${name}"
  ok "The panel accepted a restart of node ${name}."
  return 0
}

nodes_logs_flow() {
  local panel name
  panel="$(nodes_panel_choice)" || return 0
  nodes_load_interface "$panel" || return 1
  name="$(node_ask_name "$panel")" || return 0
  node_logs "$name" || return 1
  return 0
}

nodes_detail_flow() {
  local panel name
  panel="$(nodes_panel_choice)" || return 0
  nodes_load_interface "$panel" || return 1
  ui_title "Node - $(panel_display_for "$panel")"
  name="$(node_ask_name "$panel")" || return 0
  ui_title "Node ${name} - $(panel_display_for "$panel")"
  printf 'Recorded address: %s:%s\n' \
    "$(node_record_read "$panel" "$name" NODE_HOST)" \
    "$(node_record_read "$panel" "$name" NODE_PORT)"
  printf 'Recorded role: %s\n' "$(node_record_read "$panel" "$name" NODE_ROLE)"
  printf 'Recorded fingerprint: %s\n\n' "$(node_record_read "$panel" "$name" NODE_FINGERPRINT)"
  if ! node_show "$name"; then
    warn "The panel did not answer for this node."
    return 1
  fi
  return 0
}

nodes_menu() {
  local choice
  while true; do
    ui_title "Servers"
    printf '1) List nodes and their status\n'
    printf '2) Add a node\n'
    printf '3) Show one node\n'
    printf '4) Restart a node\n'
    printf '5) Node logs\n'
    printf '6) Remove a node (deregister only)\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) nodes_list_menu ;;
    2)
      nodes_add_flow || true
      pause
      ;;
    3)
      nodes_detail_flow || true
      pause
      ;;
    4)
      nodes_restart_flow || true
      pause
      ;;
    5)
      nodes_logs_flow || true
      pause
      ;;
    6)
      nodes_remove_flow || true
      pause
      ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

# Non-interactive entry used by the command interface.
nodes_cli() {
  local command="${1:-}" panel name
  shift || true
  case "$command" in
  list)
    printf '  %-10s %-18s %-22s %-14s %s\n' PANEL NODE ADDRESS STATUS REGISTERED
    nodes_list_lines
    ;;
  add)
    need_root || return 1
    panel="${1:-}"
    name="${2:-}"
    role="${3:-}"
    host="${4:-}"
    port="${5:-}"
    fingerprint="${6:-}"
    tls="${7:-1}"
    [[ -n "$panel" && -n "$name" && -n "$role" && -n "$host" && -n "$port" ]] || {
      err "Usage: BaToHub --nodes add <panel> <node> <role> <address> <port> [fingerprint] [tls]"
      return 2
    }
    [[ "$tls" == "0" || "$tls" == "1" ]] || {
      err "tls must be 0 or 1, not ${tls}"
      return 2
    }
    node_panel_supports_nodes "$panel" || {
      err "Panel ${panel} does not declare node support."
      return 2
    }
    nodes_load_interface "$panel" || return 1
    nodes_validate_registration "$panel" "$name" "$role" "$host" "$port" "$fingerprint" || return 1
    nodes_register_node "$panel" "$name" "$role" "$host" "$port" "$fingerprint" "$tls" || return 1
    ;;
  remove)
    need_root || return 1
    panel="${1:-}"
    name="${2:-}"
    [[ -n "$panel" && -n "$name" ]] || {
      err "Usage: BaToHub --nodes remove <panel> <node>"
      return 2
    }
    nodes_remove_node "$panel" "$name" || return 1
    ;;
  panels)
    node_panels_with_nodes
    ;;
  panel-list)
    panel="${1:-}"
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --nodes panel-list <panel>"
      return 2
    }
    node_panel_supports_nodes "$panel" || {
      err "Panel ${panel} does not declare node support."
      return 2
    }
    nodes_load_interface "$panel" || return 1
    node_list
    ;;
  show)
    panel="${1:-}"
    name="${2:-}"
    [[ -n "$panel" && -n "$name" ]] || {
      err "Usage: BaToHub --nodes show <panel> <node>"
      return 2
    }
    nodes_load_interface "$panel" || return 1
    node_show "$name"
    ;;
  restart)
    need_root || return 1
    panel="${1:-}"
    name="${2:-}"
    [[ -n "$panel" && -n "$name" ]] || {
      err "Usage: BaToHub --nodes restart <panel> <node>"
      return 2
    }
    nodes_load_interface "$panel" || return 1
    node_restart "$name" || return 1
    nodes_log "restart panel=${panel} node=${name}"
    ok "The panel accepted a restart of node ${name}."
    ;;
  logs)
    panel="${1:-}"
    name="${2:-}"
    [[ -n "$panel" && -n "$name" ]] || {
      err "Usage: BaToHub --nodes logs <panel> <node>"
      return 2
    }
    nodes_load_interface "$panel" || return 1
    node_logs "$name"
    ;;
  bundle)
    panel="${1:-}"
    name="${2:-}"
    [[ -n "$panel" && -n "$name" ]] || {
      err "Usage: BaToHub --nodes bundle <panel> <node>"
      return 2
    }
    node_record_exists "$panel" "$name" || {
      err "No node named ${name} is registered for ${panel}."
      return 1
    }
    nodes_connection_bundle "$panel" "$name" \
      "$(node_record_read "$panel" "$name" NODE_HOST)" \
      "$(node_record_read "$panel" "$name" NODE_PORT)" \
      "$(node_record_read "$panel" "$name" NODE_ROLE)" \
      "$(node_record_read "$panel" "$name" NODE_FINGERPRINT)"
    ;;
  *)
    err "Unknown nodes command: ${command:-<none>}"
    printf 'Nodes commands: list, panels, panel-list, show, restart, logs, bundle\n'
    return 2
    ;;
  esac
}
